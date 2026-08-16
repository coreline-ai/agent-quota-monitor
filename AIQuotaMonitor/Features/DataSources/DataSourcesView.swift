import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DataSourcesView: View {
    let snapshots: [ProviderSnapshot]
    @State private var exportFormat = ExportFormat.json
    @State private var preview = ""
    @State private var exportStatus = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("데이터 소스").font(.largeTitle.bold()).accessibilityIdentifier("dashboard.dataSources.title")
                Text("원본 payload와 계정 식별자는 저장하지 않습니다.").foregroundStyle(.secondary)
                ForEach(snapshots) { snapshot in
                    SignalPanel(title: snapshot.provider.displayName) {
                        LabeledContent("상태") { ProviderStateBadge(state: snapshot.state) }
                        LabeledContent("계약") { Text(contract(for: snapshot.provider).rawValue) }
                        LabeledContent("인증") { Text(authentication(for: snapshot.provider)) }
                        LabeledContent("마지막 성공") {
                            Text(snapshot.lastSuccessAt?.formatted() ?? "없음")
                        }
                        LabeledContent("Fallback") {
                            Text(snapshot.windows.isEmpty ? "수치 생성 안 함" : "last-known-good cache")
                        }
                    }
                }
                SignalPanel(title: "Redacted 내보내기 미리보기") {
                    HStack {
                        Picker("형식", selection: $exportFormat) {
                            ForEach(ExportFormat.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                        }
                        .frame(width: 130)
                        Button("미리보기 생성") { makePreview() }
                        Button("파일로 내보내기") { saveExport() }
                    }
                    if !exportStatus.isEmpty { Text(exportStatus).font(.caption).foregroundStyle(.secondary) }
                    if !preview.isEmpty {
                        TextEditor(text: $preview)
                            .font(.system(.caption, design: .monospaced))
                            .frame(minHeight: 150)
                            .accessibilityLabel("Redacted 내보내기 미리보기")
                    }
                }
            }
            .padding(28)
        }
        .accessibilityIdentifier("dashboard.dataSources")
    }

    private func contract(for provider: ProviderID) -> SourceContractKind {
        switch provider {
        case .claude: .documented
        case .codex: .observed
        case .grok, .zai: .experimental
        }
    }

    private func authentication(for provider: ProviderID) -> String {
        switch provider {
        case .claude: "사용자 승인 read-only snapshot"
        case .codex: "공식 CLI 계정 상태 · read-only"
        case .grok: "미지원 · cookie 수집 안 함"
        case .zai: "수동 Keychain · endpoint 미호출"
        }
    }

    private func makePreview() {
        do {
            let data = try ExportService.data(for: snapshots, format: exportFormat)
            preview = Redactor.redact(String(decoding: data, as: UTF8.self))
        } catch {
            preview = "내보내기 실패: \(Redactor.redact(error.localizedDescription))"
        }
    }

    private func saveExport() {
        do {
            let data = try ExportService.data(for: snapshots, format: exportFormat)
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "QuotaBeacon-redacted.\(exportFormat.rawValue)"
            panel.allowedContentTypes = exportFormat == .json ? [.json] : [.commaSeparatedText]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: [.atomic])
            exportStatus = "Redacted 파일 저장 완료"
        } catch {
            exportStatus = "저장 실패: \(Redactor.redact(error.localizedDescription))"
        }
    }
}
