//
//  SystemUtils.swift
//  Vectormac
//
//  System utilities — ported from vector.py
//

import Foundation
import IOKit.ps
import AppKit

class SystemUtils {
    
    static let shared = SystemUtils()
    
    let chessUsername = "azadlari"
    
    // CVUT Schedule (from vector.py)
    let schedule: [String: [(time: String, subject: String, room: String)]] = [
        "Monday": [
            (time: "09:15", subject: "Database Systems (DBS)", room: "JPB-671"),
            (time: "12:45", subject: "Computer Structures (SAP)", room: "19:155")
        ],
        "Tuesday": [
            (time: "09:15", subject: "User Interface Design (TUR)", room: "TH:A-1142"),
            (time: "14:30", subject: "User Interface Design (TUR)", room: "19:107")
        ],
        "Wednesday": [
            (time: "08:15", subject: "Math Analysis (MA1)", room: "IP:8-571"),
            (time: "12:45", subject: "Computer Networks (PS1)", room: "IP:8-671")
        ],
        "Thursday": [
            (time: "11:00", subject: "Computer Structures (SAP)", room: "TH:A-1042"),
            (time: "12:45", subject: "Math Analysis (MA1)", room: "19:301")
        ],
        "Friday": [
            (time: "12:45", subject: "Computer Networks (PS1)", room: "19:344")
        ]
    ]
    
    // MARK: - Command Router
    
    func handleCommand(_ cmd: String) -> String? {
        let lower = cmd.lowercased()
        
        if lower.contains("vital") || lower.contains("system") {
            return getVitals()
        }
        if lower.contains("battery") {
            return getBattery()
        }
        if lower.contains("class") || lower.contains("schedule") {
            return getNextClass()
        }
        if lower.contains("convert") || lower.contains("crown") {
            return convertBolt(cmd: lower)
        }
        if lower.contains("chess") || lower.contains("elo") {
            // Async — return nil to let Groq handle, or do sync
            return nil // Will be handled via Task in VoiceEngine
        }
        if lower.contains("screenshot") {
            return takeScreenshot()
        }
        if lower.contains("open ") {
            return openApp(cmd: lower)
        }
        
        return nil // Let Groq AI handle everything else
    }
    
    // MARK: - System Vitals
    
    func getVitals() -> String {
        let cpu = cpuUsage()
        let ram = ramUsage()
        return "CPU at \(cpu) percent. RAM at \(ram) percent. M-chip performing optimally, sir."
    }
    
    private func cpuUsage() -> Int {
        var loadInfo = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &loadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let user = Double(loadInfo.cpu_ticks.0)
        let system = Double(loadInfo.cpu_ticks.1)
        let idle = Double(loadInfo.cpu_ticks.2)
        let total = user + system + idle
        return total > 0 ? Int(((user + system) / total) * 100) : 0
    }
    
    private func ramUsage() -> Int {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        return Int((Double(used) / Double(total)) * 100)
    }
    
    // MARK: - Battery
    
    func getBattery() -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["-g", "batt"]
        process.standardOutput = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8),
               let range = output.range(of: #"\d+%"#, options: .regularExpression) {
                let percent = output[range]
                return "Battery at \(percent), sir."
            }
        } catch {}
        return "Unable to read battery status, sir."
    }
    
    // MARK: - Class Schedule
    
    func getNextClass() -> String {
        let now = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let day = formatter.string(from: now)
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let currentTime = timeFormatter.string(from: now)
        
        guard let classes = schedule[day] else {
            return "It's the weekend, sir. Pursue Azadox."
        }
        
        for lesson in classes {
            if lesson.time > currentTime {
                return "Next: \(lesson.subject) at \(lesson.time) in \(lesson.room)."
            }
        }
        
        return "All classes completed, sir. Gym time?"
    }
    
    // MARK: - Currency Conversion
    
    func convertBolt(cmd: String) -> String {
        let numbers = cmd.components(separatedBy: .whitespaces).compactMap { Int($0) }
        guard let amount = numbers.first else {
            return "Specify the crown amount, sir."
        }
        let azn = Double(amount) * 0.073
        return "\(amount) Crowns is \(String(format: "%.2f", azn)) Manats, sir."
    }
    
    // MARK: - Screenshot
    
    func takeScreenshot() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HHmmss"
        let filename = "SS_\(formatter.string(from: Date())).png"
        let path = NSHomeDirectory() + "/Desktop/\(filename)"
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = [path]
        do {
            try process.run()
            process.waitUntilExit()
            return "Visual captured, sir."
        } catch {
            return "Screenshot failed, sir."
        }
    }
    
    // MARK: - Open App
    
    func openApp(cmd: String) -> String {
        let appName = cmd.replacingOccurrences(of: "open", with: "")
            .trimmingCharacters(in: .whitespaces)
            .capitalized
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", appName]
        do {
            try process.run()
            return "Initiating \(appName), sir."
        } catch {
            return "Could not locate \(appName), sir."
        }
    }
}
