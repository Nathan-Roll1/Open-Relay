import SwiftUI
import Foundation
import OSLog
import UIKit
import Darwin
#if canImport(MLX)
import MLX
#endif

@main
struct FourierDeviceQA: App {
    init() {
        #if canImport(MLX)
        Memory.cacheLimit = 20 * 1024 * 1024
        #endif
    }

    var body: some Scene {
        WindowGroup { DeviceCheckView() }
    }
}

private struct DeviceCheckView: View {
    @State private var status = "Starting"
    @State private var started = false
    private let log = Logger(subsystem: "org.oruk.qa", category: "Fourier")
    var body: some View {
        Text(status).accessibilityIdentifier("fourierVerification").task {
            guard !started else { return }
            started = true
            UIApplication.shared.isIdleTimerDisabled = true
            await run()
        }
    }

    private func stage(_ value: String) {
        status = value
        log.notice("FOURIER_DEVICE \(value, privacy: .public)")
        NSLog("FOURIER_DEVICE %@", value)
    }

    private func memoryMB() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint / (1024 * 1024) : 0
    }

    @MainActor
    private func run() async {
        do {
            let service = OnDeviceASRService()
            service.switchVariant(.fourier)
            let cached = service.hasDownloadedFiles(for: .fourier)
            stage("loading cached=\(cached) footprintMiB=\(memoryMB())")
            try await service.loadModel()
            stage("loaded footprintMiB=\(memoryMB())")
            guard let url = Bundle.main.url(forResource: "fourier-orig-jfk", withExtension: "wav") else {
                stage("FAIL bundled recording missing"); return
            }
            let result = try await service.transcribe(fileURL: url)
            let words = result.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty }
            let reference = "and so my fellow americans ask not what your country can do for you ask what you can do for your country"
            let label = words.joined(separator: " ") == reference ? "PASS" : "MISMATCH"
            stage("\(label) cached=\(cached) footprintMiB=\(memoryMB()) words=\(result)")
        } catch {
            stage("FAIL \(error.localizedDescription)")
        }
    }
}
