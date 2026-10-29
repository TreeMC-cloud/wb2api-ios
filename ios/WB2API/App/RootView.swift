import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showEditor = false

    var body: some View {
        // The Safari user agent is mandatory: the console server only issues the
        // full web UI to browser-like clients.
        BrowserView(
            url: settings.isConfigured ? settings.loginURL : nil,
            allowInsecureHTTP: settings.allowInsecureHTTP,
            adminKey: settings.adminKey
        )
        .ignoresSafeArea(.container, edges: .bottom)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if settings.isConfigured { StatusBar() }
        }
        .overlay(alignment: .center) {
            if !settings.isConfigured {
                SetupPrompt { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            NavigationStack { ServerEditor(isFirstRun: !settings.isConfigured) }
                .environmentObject(settings)
        }
        .onAppear { if !settings.isConfigured { showEditor = true } }
    }
}

private struct SetupPrompt: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "server.rack")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
            Text("连接你的 wb2api 控制台")
                .font(.title3.bold())
            Text("填写服务器地址与管理密钥。服务器需要先跑起 docker compose 或桌面端。")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("配置服务器", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(28)
        .frame(maxWidth: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(radius: 18, y: 8)
        .padding(24)
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showEditor = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(.green)
            Text(settings.baseURL?.host ?? "")
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Button {
                NotificationCenter.default.post(name: .wb2apiReloadRequested, object: nil)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            Button { showEditor = true } label: {
                Image(systemName: "gearshape")
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .sheet(isPresented: $showEditor) {
            NavigationStack { ServerEditor(isFirstRun: false) }
                .environmentObject(settings)
        }
    }
}
