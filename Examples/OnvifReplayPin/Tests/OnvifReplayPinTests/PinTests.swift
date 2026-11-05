// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Checks the ONVIF replay dependency pin. Git object lookup is local.
// This file does not build the library or run a replay session.

import Foundation
import Testing

private let auditedPrefix = "4f5b0ff"
private let forkURL = "https://github.com/mENtuDeN/IPCamKit.git"
private let replaySubject =
  "Add PlayOptions: ONVIF replay (Range clock=, Require: onvif-replay) and Scale"

@Suite("ONVIF replay revision pin")
struct PinTests {

  @Test("Prefix 4f5b0ff is one commit and every pin uses it")
  func pinsMatchTheAuditedCommit() throws {
    let root = try repositoryRoot()
    let pinRoot = root.appendingPathComponent("Examples/OnvifReplayPin")
    let manifest = try String(
      contentsOf: pinRoot.appendingPathComponent("Package.swift"), encoding: .utf8)
    let revision = try revisionLiteral(in: manifest)
    #expect(revision.hasPrefix(auditedPrefix))
    #expect(revision.count == 40)

    let matches = try git(["rev-parse", "--disambiguate=\(auditedPrefix)"], at: root)
      .split(separator: "\n")
      .map(String.init)
    #expect(matches == [revision])

    let verified = try git(["rev-parse", "--verify", "\(auditedPrefix)^{commit}"], at: root)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(verified == revision)

    let subject = try git(["log", "-1", "--format=%s", revision], at: root)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(subject == replaySubject)

    let parent = try git(["rev-parse", "\(revision)^"], at: root)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let parentSubject = try git(["log", "-1", "--format=%s", parent], at: root)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    #expect(parentSubject == ":memo: Release 0.3.2 [ci skip]")

    let remoteRef = "refs/remotes/origin/onvif-replay"
    let remoteExit = gitStatus(["rev-parse", "--verify", "--quiet", remoteRef], at: root)
    if remoteExit == 0 {
      let tip = try git(["rev-parse", remoteRef], at: root)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      #expect(tip == revision)
    }

    let resolved = try resolvedRevision(pinRoot.appendingPathComponent("Package.resolved"))
    #expect(resolved == revision)

    let project = try String(
      contentsOf: pinRoot.appendingPathComponent(
        "OnvifReplayPin.xcodeproj/project.pbxproj"),
      encoding: .utf8
    )
    #expect(project.contains("kind = revision;"))
    #expect(project.contains("revision = \(revision);"))
    #expect(project.contains(forkURL))
    #expect(project.contains("branch = onvif-replay") == false)
    #expect(project.contains("kind = branch") == false)
    #expect(project.contains("MACOSX_DEPLOYMENT_TARGET = 13.0;"))
    #expect(project.contains("IPHONEOS_DEPLOYMENT_TARGET = 16.0;"))
    #expect(project.contains("TVOS_DEPLOYMENT_TARGET = 16.0;"))
    #expect(project.contains("XROS_DEPLOYMENT_TARGET = 1.0;"))

    #expect(manifest.contains("branch:") == false)
    #expect(manifest.contains(".macOS(.v13)"))
    #expect(manifest.contains(".iOS(.v16)"))
    #expect(manifest.contains(".tvOS(.v16)"))
    #expect(manifest.contains(".macCatalyst(.v16)"))
    #expect(manifest.contains(".visionOS(.v1)"))

    let docs = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
    #expect(docs.contains(revision))
    #expect(docs.contains("branch: \"onvif-replay\"") == false)
  }
}

private func revisionLiteral(in manifest: String) throws -> String {
  let needle = "revision: \""
  guard let start = manifest.range(of: needle) else {
    throw PinError("Package.swift has no revision literal")
  }
  let rest = manifest[start.upperBound...]
  guard let end = rest.firstIndex(of: "\"") else {
    throw PinError("Package.swift revision literal is unterminated")
  }
  return String(rest[..<end])
}

private func resolvedRevision(_ url: URL) throws -> String {
  let data = try Data(contentsOf: url)
  let object = try JSONSerialization.jsonObject(with: data)
  guard let root = object as? [String: Any],
    let pins = root["pins"] as? [[String: Any]],
    pins.count == 1,
    let pin = pins.first,
    pin["identity"] as? String == "ipcamkit",
    pin["location"] as? String == forkURL,
    let state = pin["state"] as? [String: Any],
    let revision = state["revision"] as? String
  else {
    throw PinError("Package.resolved does not pin one IPCamKit revision")
  }
  #expect(state["branch"] == nil)
  return revision
}

private func repositoryRoot(file: String = #filePath) throws -> URL {
  var url = URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent()
  let manager = FileManager.default
  while url.path != "/" {
    if manager.fileExists(atPath: url.appendingPathComponent(".git").path) {
      return url
    }
    url.deleteLastPathComponent()
  }
  throw PinError("Git repository root not found")
}

private func git(_ arguments: [String], at directory: URL) throws -> String {
  let result = try runGit(arguments, at: directory)
  guard result.status == 0 else {
    throw PinError("git \(arguments.joined(separator: " ")) failed")
  }
  return result.output
}

private func gitStatus(_ arguments: [String], at directory: URL) -> Int32 {
  (try? runGit(arguments, at: directory).status) ?? 1
}

private func runGit(
  _ arguments: [String], at directory: URL
) throws -> (status: Int32, output: String) {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
  process.arguments = arguments
  process.currentDirectoryURL = directory
  let output = Pipe()
  process.standardOutput = output
  process.standardError = Pipe()
  try process.run()
  process.waitUntilExit()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  let text = String(decoding: data, as: UTF8.self)
  return (process.terminationStatus, text)
}

private struct PinError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}
