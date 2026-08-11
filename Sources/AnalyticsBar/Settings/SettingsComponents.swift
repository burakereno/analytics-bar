import AppKit
import SwiftUI

struct SettingsSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(0.4)

            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .settingsCardSurface()
    }
}

struct SettingsRowLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    var isEnabled = true

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isEnabled ? .primary : .tertiary)
                Text(subtitle)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    var isEnabled = true

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle, isEnabled: isEnabled)
            Spacer(minLength: 10)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(.orange)
                .accentColor(.orange)
                .disabled(!isEnabled)
                .accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }
}

struct SettingsMenuRow<Option: Hashable>: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        selection = option
                    } label: {
                        if option == selection {
                            Label(optionTitle(option), systemImage: "checkmark")
                        } else {
                            Text(optionTitle(option))
                        }
                    }
                }
            } label: {
                Text(optionTitle(selection))
                    .lineLimit(1)
                    .font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.vertical, 3)
    }
}

struct SettingsSegmentedRow<Option: Hashable>: View {
    let icon: String
    let title: String
    let subtitle: String
    let options: [Option]
    @Binding var selection: Option
    let optionTitle: (Option) -> String

    var body: some View {
        HStack(spacing: 10) {
            SettingsRowLabel(icon: icon, title: title, subtitle: subtitle)
            Spacer(minLength: 8)
            Picker("", selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(optionTitle(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 136)
            .accentColor(.orange)
            .accessibilityLabel(title)
        }
        .padding(.vertical, 3)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.055))
            .frame(height: 0.5)
            .padding(.leading, 29)
            .padding(.vertical, 8)
    }
}

struct SettingsErrorText: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(.red)
            .padding(.leading, 29)
            .padding(.top, 5)
    }
}

struct SettingsFooterView: View {
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: refresh) {
                HStack(spacing: 6) {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                    Text("Refresh")
                }
            }
            .disabled(isRefreshing)

            Spacer()

            Label("v\(AppConfiguration.marketingVersion)", systemImage: "arrow.down.circle")

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .font(.system(size: 9, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct SettingsCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.black.opacity(0.30))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.32), radius: 8, y: 2)
    }
}

extension View {
    func settingsCardSurface() -> some View {
        modifier(SettingsCardSurface())
    }
}
