import SwiftUI

struct ServerEditor: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    let isFirstRun: Bool

    @State private var address: String = ""
    @State private var key: String = ""
    @State private var allowHTTP: Bool = false
    @State private var validationError: String?
    @State private var probing = false
    @State private var probeResult: String?

    var body: some View {
        Form {
            Section {
                TextField("https://wb2api.example.com 或 192.168.1.10:7863", text: $address)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: address) { _, _ in validationError = nil; probeResult = nil }
                SecureField("管理密钥（docker compose logs console 里可见）", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("服务器")
            } footer: {
                if let validationError {
                    Text(validationError).foregroundStyle(.red)
                } else {
                    Text("密钥保存在系统钥匙串，只有本机可读。")
                }
            }

            Section {
                Toggle("允许明文 HTTP", isOn: $allowHTTP)
            } footer: {
                Text("局域网/自建机没有证书时打开。公网地址请务必使用 HTTPS，否则密钥会明文传输。")
            }

            Section {
                Button {
                    probe()
                } label: {
                    HStack {
                        Text("测试连接")
                        Spacer()
                        if probing { ProgressView() }
                    }
                }
                .disabled(probing || parsedURL == nil)
                if let probeResult {
                    Text(probeResult)
                        .font(.footnote)
                        .foregroundStyle(probeResult.hasPrefix("✓") ? .green : .red)
                }
            }

            if !isFirstRun, settings.isConfigured {
                Section {
                    Button("清除服务器配置与密钥", role: .destructive) {
                        settings.clearCredentials()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(isFirstRun ? "首次配置" : "服务器设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                if !isFirstRun { Button("取消") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { save() }.disabled(parsedURL == nil)
            }
        }
        .onAppear {
            address = settings.serverURLString
            key = settings.adminKey
            allowHTTP = settings.allowInsecureHTTP
        }
    }

    /// Validated preview of what the user typed, using the toggle state.
    private var parsedURL: URL? {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        if !raw.contains("://") { raw = (allowHTTP ? "http://" : "https://") + raw }
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty
        else { return nil }
        return components.url
    }

    private func save() {
        guard let url = parsedURL else {
            validationError = "地址格式不正确"
            return
        }
        settings.allowInsecureHTTP = allowHTTP
        settings.serverURLString = url.absoluteString
        settings.adminKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        dismiss()
    }

    private func probe() {
        guard let base = parsedURL else { return }
        probing = true
        probeResult = nil
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        components?.path = "/livez"
        components?.query = nil
        guard let probeURL = components?.url else { probing = false; return }
        var request = URLRequest(url: probeURL)
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        URLSession.shared.dataTask(with: request) { data, response, error in
            // URLSession calls back on a background queue; @State writes must
            // hop to the main actor or SwiftUI mutates off-thread.
            let message: String
            if let error {
                message = "✗ 连接失败：\(error.localizedDescription)"
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                if code == 200 {
                    let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                    message = "✓ 服务在线（/livez 200）" + (trimmed.isEmpty ? "" : " · \(trimmed.prefix(60))")
                } else {
                    message = "✗ 服务返回 \(code)"
                }
            }
            DispatchQueue.main.async {
                probing = false
                probeResult = message
            }
        }.resume()
    }
}
