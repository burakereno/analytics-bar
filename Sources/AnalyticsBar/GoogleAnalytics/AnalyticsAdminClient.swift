import Foundation

protocol AnalyticsAdminClientProtocol: Sendable {
    func listProperties(accessToken: String) async throws -> [AnalyticsProperty]
}

struct AnalyticsAdminClient: AnalyticsAdminClientProtocol, Sendable {
    private struct AccountSummariesResponse: Decodable, Sendable {
        let accountSummaries: [AccountSummary]?
        let nextPageToken: String?
    }

    private struct AccountSummary: Decodable, Sendable {
        let account: String
        let displayName: String
        let propertySummaries: [PropertySummary]?
    }

    private struct PropertySummary: Decodable, Sendable {
        let property: String
        let displayName: String
    }

    private struct PropertyDetail: Decodable, Sendable {
        let name: String
        let timeZone: String
        let currencyCode: String
    }

    private struct PropertySeed: Sendable {
        let accountResourceName: String
        let accountDisplayName: String
        let resourceName: String
        let displayName: String
    }

    private let httpClient: any HTTPClient
    private let decoder = JSONDecoder()

    init(httpClient: any HTTPClient) {
        self.httpClient = httpClient
    }

    func listProperties(accessToken: String) async throws -> [AnalyticsProperty] {
        let seeds = try await listPropertySeeds(accessToken: accessToken)
        var properties: [AnalyticsProperty] = []

        for batchStart in stride(from: 0, to: seeds.count, by: 4) {
            let batch = Array(seeds[batchStart..<min(batchStart + 4, seeds.count)])
            let values = try await withThrowingTaskGroup(
                of: AnalyticsProperty.self,
                returning: [AnalyticsProperty].self
            ) { group in
                for seed in batch {
                    group.addTask {
                        try await property(from: seed, accessToken: accessToken)
                    }
                }
                var batchValues: [AnalyticsProperty] = []
                for try await value in group {
                    batchValues.append(value)
                }
                return batchValues
            }
            properties.append(contentsOf: values)
        }

        return properties.sorted {
            let accountOrder = $0.accountDisplayName.localizedCaseInsensitiveCompare($1.accountDisplayName)
            if accountOrder != .orderedSame { return accountOrder == .orderedAscending }
            return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private func listPropertySeeds(accessToken: String) async throws -> [PropertySeed] {
        var seeds: [PropertySeed] = []
        var pageToken: String?
        var seenTokens = Set<String>()

        repeat {
            var components = URLComponents(string: "https://analyticsadmin.googleapis.com/v1alpha/accountSummaries")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
            if let pageToken {
                components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken))
            }
            let data = try await get(url: components.url!, accessToken: accessToken)
            let page: AccountSummariesResponse
            do {
                page = try decoder.decode(AccountSummariesResponse.self, from: data)
            } catch {
                throw GoogleAPIError.invalidResponse
            }

            for account in page.accountSummaries ?? [] {
                for property in account.propertySummaries ?? [] {
                    guard Self.propertyID(from: property.property) != nil else {
                        throw GoogleAPIError.invalidResponse
                    }
                    seeds.append(
                        PropertySeed(
                            accountResourceName: account.account,
                            accountDisplayName: account.displayName,
                            resourceName: property.property,
                            displayName: property.displayName
                        )
                    )
                }
            }

            pageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
            if let pageToken, !seenTokens.insert(pageToken).inserted {
                throw GoogleAPIError.invalidResponse
            }
        } while pageToken != nil

        return seeds
    }

    private func property(from seed: PropertySeed, accessToken: String) async throws -> AnalyticsProperty {
        guard let id = Self.propertyID(from: seed.resourceName),
              let url = URL(string: "https://analyticsadmin.googleapis.com/v1beta/properties/\(id)") else {
            throw GoogleAPIError.invalidResponse
        }
        let data = try await get(url: url, accessToken: accessToken)
        let detail: PropertyDetail
        do {
            detail = try decoder.decode(PropertyDetail.self, from: data)
        } catch {
            throw GoogleAPIError.invalidResponse
        }
        guard detail.name == seed.resourceName else { throw GoogleAPIError.invalidResponse }

        return AnalyticsProperty(
            id: id,
            resourceName: seed.resourceName,
            accountResourceName: seed.accountResourceName,
            accountDisplayName: seed.accountDisplayName,
            displayName: seed.displayName,
            timeZoneIdentifier: detail.timeZone,
            currencyCode: detail.currencyCode
        )
    }

    private func get(url: URL, accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AnalyticsBar/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await httpClient.data(for: request)
        if let error = GoogleHTTPStatusMapper.error(for: response) { throw error }
        return data
    }

    private static func propertyID(from resourceName: String) -> String? {
        let parts = resourceName.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0] == "properties",
              !parts[1].isEmpty,
              parts[1].allSatisfy(\.isNumber) else {
            return nil
        }
        return String(parts[1])
    }
}
