import Foundation

// The system ps is setuid: native APIs cannot read every system process as a user.
// Keep one consistent CPU metric and full process coverage instead of mixing
// accessible-process interval samples with inaccessible-process lifetime averages.
enum ProcessStats {
    private static var currentAppProcessNames: Set<String> {
        [
            Bundle.main.executableURL?.lastPathComponent,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .reduce(into: Set<String>()) { names, name in
            names.insert(name.lowercased())
        }
    }

    /// Get top N processes sorted by CPU usage
    /// Uses: ps -Aceo pcpu,pmem,comm -r
    static func getTopCPUProcesses(count: Int = 5) async -> [TopProcess] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/bin/ps")
                // -A: all processes
                // -c: show only command name (not full path)
                // -e: show environment (needed for some systems)
                // -o: output format
                // -r: sort by CPU (descending)
                task.arguments = ["-Aceo", "pcpu,pmem,comm", "-r"]

                let pipe = Pipe()
                task.standardOutput = pipe
                task.standardError = FileHandle.nullDevice

                do {
                    try task.run()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    task.waitUntilExit()

                    let output = String(data: data, encoding: .utf8) ?? ""

                    let processes = parseProcessOutput(output, maxCount: count)
                    continuation.resume(returning: processes)
                } catch {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    /// Parse ps command output
    /// Format: %CPU %MEM COMMAND
    private static func parseProcessOutput(_ output: String, maxCount: Int) -> [TopProcess] {
        var processes: [TopProcess] = []
        let lines = output.components(separatedBy: "\n")

        var lineIndex = 0
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Skip header line (contains "CPU" or "%")
            if lineIndex == 0 {
                lineIndex += 1
                if trimmed.lowercased().contains("cpu") || trimmed.contains("%") {
                    continue
                }
            }

            // Parse data line
            let fields = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard fields.count >= 3 else { continue }

            guard let cpuPercent = Double(fields[0]),
                  let memPercent = Double(fields[1]) else { continue }

            // Command name is the last field (may contain spaces, take all remaining)
            var name = fields[2..<fields.count].joined(separator: " ")

            // Strip path if present (take last component after /)
            if let lastSlash = name.lastIndex(of: "/") {
                name = String(name[name.index(after: lastSlash)...])
            }

            if currentAppProcessNames.contains(name.lowercased()) {
                continue
            }

            // Skip very low CPU processes
            if cpuPercent < 0.1 { continue }

            processes.append(TopProcess(
                name: name,
                cpuPercent: cpuPercent,
                memPercent: memPercent
            ))

            // Limit results
            if processes.count >= maxCount {
                break
            }

            lineIndex += 1
        }

        return processes
    }
}
