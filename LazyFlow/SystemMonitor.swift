import Foundation
import IOKit

@Observable
final class SystemMonitor {

    // MARK: - GPU
    var gpuUtil:   Double = 0
    var gpuRender: Double = 0
    var gpuTiler:  Double = 0
    var gpuHistory: [Double]

    // MARK: - CPU
    var cpuTotal: Double = 0
    var cpuCores: [Double] = []
    var cpuHistory: [Double]

    // MARK: - RAM
    var ramUsed:       Double = 0
    var ramTotal:      Double = 0
    var ramWired:      Double = 0
    var ramCompressed: Double = 0
    var ramHistory: [Double]

    // MARK: - Private state
    private static let histLen = 40
    private var timer: Timer?
    private var prevLoadInfo: host_cpu_load_info?
    private var prevCpuArr:   processor_info_array_t?
    private var prevCpuCount: mach_msg_type_number_t = 0

    init() {
        let zeros = [Double](repeating: 0, count: Self.histLen)
        gpuHistory = zeros
        cpuHistory = zeros
        ramHistory = zeros
        loadRAMTotal()
    }

    private func loadRAMTotal() {
        var info  = host_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_basic_info>.stride / MemoryLayout<integer_t>.stride)
        withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                _ = host_info(mach_host_self(), HOST_BASIC_INFO, $0, &count)
            }
        }
        ramTotal = Double(info.max_mem)
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func refresh() {
        refreshGPU()
        refreshCPU()
        refreshRAM()
    }

    // MARK: - GPU (IOAccelerator PerformanceStatistics)
    private func refreshGPU() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("IOAccelerator"), &iter) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iter) }

        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            var raw: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(entry, &raw, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                  let dict  = raw?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }

            gpuUtil   = clamp(stats["Device Utilization %"] as? Int ?? stats["GPU Activity(%)"] as? Int ?? 0)
            gpuRender = clamp(stats["Renderer Utilization %"] as? Int ?? 0)
            gpuTiler  = clamp(stats["Tiler Utilization %"]    as? Int ?? 0)
            push(&gpuHistory, gpuUtil)
            return
        }
    }

    // MARK: - CPU (host_statistics + host_processor_info delta)
    private func refreshCPU() {
        var load  = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        let kr = withUnsafeMutablePointer(to: &load) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        if kr == KERN_SUCCESS, let prev = prevLoadInfo {
            let u = Double(load.cpu_ticks.0) - Double(prev.cpu_ticks.0)
            let s = Double(load.cpu_ticks.1) - Double(prev.cpu_ticks.1)
            let i = Double(load.cpu_ticks.2) - Double(prev.cpu_ticks.2)
            let n = Double(load.cpu_ticks.3) - Double(prev.cpu_ticks.3)
            let t = u + s + i + n
            if t > 0 {
                cpuTotal = max(0, min(1, (u + s + n) / t))
                push(&cpuHistory, cpuTotal)
            }
        }
        if kr == KERN_SUCCESS { prevLoadInfo = load }

        // Per-core
        var numCPUs: natural_t = 0
        var cpuArr:  processor_info_array_t?
        var cpuInfo: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
              &numCPUs, &cpuArr, &cpuInfo) == KERN_SUCCESS, let arr = cpuArr else { return }

        let n = Int(numCPUs)
        var cores = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let b = Int(CPU_STATE_MAX) * i
            if let p = prevCpuArr {
                let du = arr[b + Int(CPU_STATE_USER)]   - p[b + Int(CPU_STATE_USER)]
                let ds = arr[b + Int(CPU_STATE_SYSTEM)] - p[b + Int(CPU_STATE_SYSTEM)]
                let dn = arr[b + Int(CPU_STATE_NICE)]   - p[b + Int(CPU_STATE_NICE)]
                let di = arr[b + Int(CPU_STATE_IDLE)]   - p[b + Int(CPU_STATE_IDLE)]
                let active = du + ds + dn
                let total  = active + di
                cores[i] = total > 0 ? max(0, min(1, Double(active) / Double(total))) : 0
            } else {
                let active = arr[b + Int(CPU_STATE_USER)] + arr[b + Int(CPU_STATE_SYSTEM)] + arr[b + Int(CPU_STATE_NICE)]
                let total  = active + arr[b + Int(CPU_STATE_IDLE)]
                cores[i] = total > 0 ? max(0, min(1, Double(active) / Double(total))) : 0
            }
        }
        cpuCores = cores

        if let p = prevCpuArr {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: p)),
                          vm_size_t(prevCpuCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        prevCpuArr   = arr
        prevCpuCount = cpuInfo
    }

    // MARK: - RAM (host_statistics64)
    private func refreshRAM() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) { p in
            p.withMemoryRebound(to: integer_t.self, capacity: 1) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return }

        let pg  = Double(vm_page_size)
        let active      = Double(stats.active_count)          * pg
        let speculative = Double(stats.speculative_count)     * pg
        let inactive    = Double(stats.inactive_count)        * pg
        let wired       = Double(stats.wire_count)            * pg
        let compressed  = Double(stats.compressor_page_count) * pg
        let purgeable   = Double(stats.purgeable_count)       * pg
        let external    = Double(stats.external_page_count)   * pg

        ramUsed       = active + inactive + speculative + wired + compressed - purgeable - external
        ramWired      = wired
        ramCompressed = compressed
        if ramTotal > 0 { push(&ramHistory, min(1, ramUsed / ramTotal)) }
    }

    // MARK: - Helpers
    private func clamp(_ pct: Int) -> Double { Double(max(0, min(100, pct))) / 100 }
    private func push(_ arr: inout [Double], _ val: Double) { arr.removeFirst(); arr.append(val) }

    deinit {
        stop()
        if let p = prevCpuArr {
            vm_deallocate(mach_task_self_,
                          vm_address_t(UInt(bitPattern: p)),
                          vm_size_t(prevCpuCount) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
    }
}
