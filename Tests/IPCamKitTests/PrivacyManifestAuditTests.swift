// Copyright (c) 2026 Steel Brain
// SPDX-License-Identifier: MIT
// Static audit of UserDefaults required-reason API CA92.1.
//
// Apple permits CA92.1 only for reading and writing information that stays
// inside the app container (UserDefaults.standard / a nil suite). It does not
// permit App Group or named-suite defaults, defaults shared with other apps
// or the system, or an unclassified wrapper. NVRStore is unclassified only
// when the same file also calls a defaults API. This file checks source text and
// property lists. It does not archive an app and it does not produce an Xcode
// privacy report.

import Foundation
import Testing

// MARK: - Policy

private enum UserDefaultsPrivacyUse: Equatable {
  case none
  case appPrivate
  case suiteOrAppGroup
  case systemOrForeignDomain
  case unclassifiedWrapper
}

private enum CA921Decision: Equatable {
  case omit
  case declareSingleCA921
  case refuse(String)
}

private struct ParsedManifest: Equatable {
  var isValidPlist: Bool
  var userDefaultsEntries: Int
  var userDefaultsReasonCodes: [String]
}

private let sdkPrivacyManifestPath = "Sources/IPCamKit/PrivacyInfo.xcprivacy"

private func ca921Decision(
  use: UserDefaultsPrivacyUse,
  manifests: [ParsedManifest]
) -> CA921Decision {
  if manifests.contains(where: { !$0.isValidPlist }) {
    return .refuse("A PrivacyInfo.xcprivacy file is not a valid property list")
  }
  let entries = manifests.reduce(0) { $0 + $1.userDefaultsEntries }
  let codes = manifests.flatMap(\.userDefaultsReasonCodes)
  switch use {
  case .none:
    if entries == 0 && codes.isEmpty {
      return .omit
    }
    return .refuse(
      "UserDefaults reason \(codes) is declared but no app-private UserDefaults call exists"
    )
  case .appPrivate:
    if manifests.count == 1 && entries == 1 && codes == ["CA92.1"] {
      return .declareSingleCA921
    }
    return .refuse(
      "App-private UserDefaults requires exactly one CA92.1 entry; found \(entries) entries \(codes)"
    )
  case .suiteOrAppGroup:
    return .refuse("App Group or named-suite UserDefaults does not match CA92.1")
  case .systemOrForeignDomain:
    return .refuse("CFPreferences access beyond the app container does not match CA92.1")
  case .unclassifiedWrapper:
    return .refuse("NVRStore is not app-private UserDefaults use, so CA92.1 does not match")
  }
}

private func includedOnce(
  decision: CA921Decision,
  manifestPaths: [String],
  packageSwiftMentions: Int,
  pbxprojResourcePhaseMentions: Int
) -> Bool {
  let explicitCopies = packageSwiftMentions + pbxprojResourcePhaseMentions
  switch decision {
  case .declareSingleCA921:
    // Xcode copies PrivacyInfo.xcprivacy from the Swift package target root.
    // Listing it again in Package.swift resources or in a pbxproj Resources
    // phase puts a second copy in the archive.
    return manifestPaths == [sdkPrivacyManifestPath] && explicitCopies == 0
  case .omit:
    if manifestPaths.isEmpty {
      return explicitCopies == 0
    }
    return manifestPaths.count == 1 && explicitCopies == 0
  case .refuse:
    return false
  }
}

// MARK: - Source classification

private func sourceForAPIScan(_ source: String) -> String {
  var output: [Character] = []
  let chars = Array(source)
  var index = 0

  enum FrameKind {
    case code
    case lineComment
    case blockComment
    case string
    case tripleString
    case interpolation
  }

  struct Frame {
    var kind: FrameKind
    var parenDepth: Int
  }

  var stack = [Frame(kind: .code, parenDepth: 0)]

  func starts(with needle: String, at start: Int) -> Bool {
    let needleChars = Array(needle)
    guard start + needleChars.count <= chars.count else { return false }
    for offset in needleChars.indices {
      if chars[start + offset] != needleChars[offset] {
        return false
      }
    }
    return true
  }

  while index < chars.count {
    let kind = stack[stack.count - 1].kind
    let char = chars[index]
    if kind == .code || kind == .interpolation {
      if kind == .interpolation && char == "(" {
        stack[stack.count - 1].parenDepth += 1
        output.append(char)
        index += 1
        continue
      }
      if kind == .interpolation && char == ")" {
        stack[stack.count - 1].parenDepth -= 1
        if stack[stack.count - 1].parenDepth == 0 {
          _ = stack.popLast()
          output.append(" ")
        } else {
          output.append(char)
        }
        index += 1
        continue
      }
      if starts(with: "//", at: index) {
        stack.append(Frame(kind: .lineComment, parenDepth: 0))
        index += 2
        continue
      }
      if starts(with: "/*", at: index) {
        stack.append(Frame(kind: .blockComment, parenDepth: 0))
        index += 2
        continue
      }
      if starts(with: "\"\"\"", at: index) {
        stack.append(Frame(kind: .tripleString, parenDepth: 0))
        output.append(contentsOf: "\"\"")
        index += 3
        continue
      }
      if char == "\"" {
        stack.append(Frame(kind: .string, parenDepth: 0))
        output.append(contentsOf: "\"\"")
        index += 1
        continue
      }
      output.append(char)
      index += 1
      continue
    }
    if kind == .lineComment {
      if char == "\n" {
        _ = stack.popLast()
        output.append("\n")
      }
      index += 1
      continue
    }
    if kind == .blockComment {
      if starts(with: "*/", at: index) {
        _ = stack.popLast()
        index += 2
      } else {
        if char == "\n" {
          output.append("\n")
        }
        index += 1
      }
      continue
    }
    if kind == .string || kind == .tripleString {
      let closing = kind == .tripleString ? "\"\"\"" : "\""
      if starts(with: closing, at: index) {
        _ = stack.popLast()
        index += closing.count
        continue
      }
      if char == "\\" && index + 1 < chars.count && chars[index + 1] == "(" {
        stack.append(Frame(kind: .interpolation, parenDepth: 1))
        output.append(" ")
        index += 2
        continue
      }
      if kind == .string && char == "\\" && index + 1 < chars.count {
        index += 2
        continue
      }
      if char == "\n" {
        output.append("\n")
      }
      index += 1
      continue
    }
  }
  return String(output)
}

private func containsIdentifier(_ source: String, _ identifier: String) -> Bool {
  let chars = Array(source)
  let needle = Array(identifier)
  guard !needle.isEmpty else { return false }
  var index = 0
  while index + needle.count <= chars.count {
    var matches = true
    for offset in needle.indices {
      if chars[index + offset] != needle[offset] {
        matches = false
        break
      }
    }
    if matches {
      let beforeOK = index == 0 || !isIdentifierCharacter(chars[index - 1])
      let afterIndex = index + needle.count
      let afterOK = afterIndex == chars.count || !isIdentifierCharacter(chars[afterIndex])
      if beforeOK && afterOK {
        return true
      }
    }
    index += 1
  }
  return false
}

private func isIdentifierCharacter(_ character: Character) -> Bool {
  character.isLetter || character.isNumber || character == "_"
}

private func slicesAfterIdentifier(_ source: String, _ identifier: String) -> [String] {
  var slices: [String] = []
  let chars = Array(source)
  let needle = Array(identifier)
  var index = 0
  while index + needle.count <= chars.count {
    var matches = true
    for offset in needle.indices {
      if chars[index + offset] != needle[offset] {
        matches = false
        break
      }
    }
    let beforeOK = index == 0 || !isIdentifierCharacter(chars[index - 1])
    let afterIndex = index + needle.count
    let afterOK = afterIndex == chars.count || !isIdentifierCharacter(chars[afterIndex])
    if matches && beforeOK && afterOK {
      slices.append(String(chars[afterIndex...]))
      index = afterIndex
    } else {
      index += 1
    }
  }
  return slices
}

private func isNilSuiteArgument(_ remainder: String) -> Bool {
  var rest = remainder.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
  guard rest.first == ":" else { return false }
  rest = rest.dropFirst()
  rest = rest.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
  guard rest.hasPrefix("nil") else { return false }
  let after = rest.dropFirst(3)
  if let next = after.first {
    return !isIdentifierCharacter(next)
  }
  return true
}

private func suiteArgumentsAreNilLiterals(_ source: String) -> Bool {
  let labels = ["suiteName", "initWithSuiteName"]
  var sawLabel = false
  for label in labels {
    for remainder in slicesAfterIdentifier(source, label) {
      sawLabel = true
      if !isNilSuiteArgument(remainder) {
        return false
      }
    }
  }
  return sawLabel
}

private func hasNonStandardAppStorageStore(_ source: String) -> Bool {
  for remainder in slicesAfterIdentifier(source, "AppStorage") {
    let trimmed = remainder.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
    guard trimmed.first == "(" else { continue }
    var depth = 0
    var argument = ""
    for character in trimmed {
      if character == "(" {
        depth += 1
        if depth > 1 {
          argument.append(character)
        }
        continue
      }
      if character == ")" {
        depth -= 1
        if depth == 0 {
          break
        }
        argument.append(character)
        continue
      }
      if depth >= 1 {
        argument.append(character)
      }
    }
    for storeRemainder in slicesAfterIdentifier(argument, "store") {
      var rest = storeRemainder.drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
      guard rest.first == ":" else { continue }
      rest = rest.dropFirst().drop(while: { $0 == " " || $0 == "\n" || $0 == "\t" })
      if rest.hasPrefix(".standard") || rest.hasPrefix("UserDefaults.standard") {
        continue
      }
      return true
    }
  }
  return false
}

private func classifyUserDefaultsUse(source: String) -> UserDefaultsPrivacyUse {
  let scanned = sourceForAPIScan(source)
  if containsIdentifier(scanned, "NVRStore") {
    let defaultsAPI = ["UserDefaults", "NSUserDefaults", "AppStorage", "CFPreferences"]
    if defaultsAPI.contains(where: { containsIdentifier(scanned, $0) }) {
      return .unclassifiedWrapper
    }
  }
  if containsIdentifier(scanned, "CFPreferences") {
    return .systemOrForeignDomain
  }
  let suiteLabels = ["suiteName", "initWithSuiteName"]
  if suiteLabels.contains(where: { containsIdentifier(scanned, $0) }) {
    if !suiteArgumentsAreNilLiterals(scanned) {
      return .suiteOrAppGroup
    }
  }
  if hasNonStandardAppStorageStore(scanned) {
    return .suiteOrAppGroup
  }
  let direct = ["UserDefaults", "NSUserDefaults", "AppStorage"]
  if direct.contains(where: { containsIdentifier(scanned, $0) }) {
    return .appPrivate
  }
  return .none
}

private func mergeUses(_ uses: [UserDefaultsPrivacyUse]) -> UserDefaultsPrivacyUse {
  if uses.contains(.unclassifiedWrapper) {
    return .unclassifiedWrapper
  }
  if uses.contains(.systemOrForeignDomain) {
    return .systemOrForeignDomain
  }
  if uses.contains(.suiteOrAppGroup) {
    return .suiteOrAppGroup
  }
  if uses.contains(.appPrivate) {
    return .appPrivate
  }
  return .none
}

// MARK: - Manifest and project parsing

private func propertyListData(_ data: Data) -> Data {
  guard var text = String(data: data, encoding: .utf8) else { return data }
  if let start = text.range(of: "<!DOCTYPE"),
    let end = text.range(of: ">", range: start.lowerBound..<text.endIndex)
  {
    text.removeSubrange(start.lowerBound..<end.upperBound)
  }
  return Data(text.utf8)
}

private func parsePrivacyManifest(_ data: Data) -> ParsedManifest {
  let payload = propertyListData(data)
  var format = PropertyListSerialization.PropertyListFormat.xml
  guard
    let object = try? PropertyListSerialization.propertyList(
      from: payload, options: [], format: &format),
    let root = object as? [String: Any]
  else {
    return ParsedManifest(isValidPlist: false, userDefaultsEntries: 0, userDefaultsReasonCodes: [])
  }
  guard let accessed = root["NSPrivacyAccessedAPITypes"] as? [Any] else {
    return ParsedManifest(isValidPlist: true, userDefaultsEntries: 0, userDefaultsReasonCodes: [])
  }
  var entries = 0
  var codes: [String] = []
  for item in accessed {
    guard let entry = item as? [String: Any] else {
      return ParsedManifest(
        isValidPlist: false, userDefaultsEntries: 0, userDefaultsReasonCodes: [])
    }
    let apiType = entry["NSPrivacyAccessedAPIType"] as? String
    guard apiType == "NSPrivacyAccessedAPICategoryUserDefaults" else {
      continue
    }
    entries += 1
    let reasons = entry["NSPrivacyAccessedAPITypeReasons"] as? [String] ?? []
    codes.append(contentsOf: reasons)
  }
  return ParsedManifest(
    isValidPlist: true, userDefaultsEntries: entries, userDefaultsReasonCodes: codes)
}

private func pbxprojResourcePhaseMentions(_ project: String) -> Int {
  guard let begin = project.range(of: "/* Begin PBXResourcesBuildPhase section */"),
    let end = project.range(
      of: "/* End PBXResourcesBuildPhase section */", range: begin.upperBound..<project.endIndex)
  else {
    return 0
  }
  let section = project[begin.upperBound..<end.lowerBound]
  var count = 0
  var search = section.startIndex
  while let found = section.range(of: "PrivacyInfo.xcprivacy", range: search..<section.endIndex) {
    count += 1
    search = found.upperBound
  }
  return count
}

// MARK: - Repository scan

private struct RepositoryPrivacyAudit {
  var libraryUse: UserDefaultsPrivacyUse
  var exampleUse: UserDefaultsPrivacyUse
  var manifestPaths: [String]
  var manifests: [ParsedManifest]
  var packageSwiftMentions: Int
  var pbxprojResourcePhaseMentions: Int
  var dependencyMarkers: [String]
  var embeddedSDKBundles: [String]
  var keychainFiles: [String]
  var atsFiles: [String]
  var preferencesBundles: [String]
  var otherRequiredReasonFiles: [String]
  var skippedSensitivePaths: [String]
}

private let keychainTokens = ["SecItem", "kSecClass", "SecKeychain"]
private let atsTokens = [
  "NSAppTransportSecurity",
  "NSAllowsArbitraryLoads",
  "NSAllowsArbitraryLoadsInWebContent",
  "NSExceptionDomains",
]
private let otherRequiredReasonTokens = [
  "systemUptime",
  "mach_absolute_time",
  "getattrlist",
  "getattrlistat",
  "volumeAvailableCapacity",
  "NSFileSystemFreeSize",
  "contentModificationDateKey",
  "creationDateKey",
  "activeInputModes",
  "UITextInputMode",
]
private let skippedDirectories: Set<String> = [".git", ".build", ".swiftpm", "DerivedData"]

private func isSensitivePath(_ name: String) -> Bool {
  let lowered = name.lowercased()
  if lowered == ".env" || lowered.hasPrefix(".env.") {
    return true
  }
  if lowered.contains("password") || lowered.contains("secret") || lowered.contains("credential") {
    return true
  }
  let blockedSuffixes = [".pem", ".p12", ".key"]
  return blockedSuffixes.contains(where: { lowered.hasSuffix($0) })
}

private func relativePath(from root: URL, _ item: URL) -> String {
  let rootPath = root.standardizedFileURL.path
  let itemPath = item.standardizedFileURL.path
  let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
  if itemPath.hasPrefix(prefix) {
    return String(itemPath.dropFirst(prefix.count))
  }
  return item.lastPathComponent
}

private func repositoryRoot(file: String = #filePath) -> URL {
  var url = URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent()
  let manager = FileManager.default
  while url.path != "/" {
    if manager.fileExists(atPath: url.appendingPathComponent("Package.swift").path) {
      return url
    }
    url.deleteLastPathComponent()
  }
  return URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent()
}

private func scanRepository(root: URL) throws -> RepositoryPrivacyAudit {
  let manager = FileManager.default
  guard
    let enumerator = manager.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [])
  else {
    throw ScanError("Unable to enumerate \(root.path)")
  }

  var librarySources: [String] = []
  var exampleSources: [String] = []
  var manifestPaths: [String] = []
  var manifests: [ParsedManifest] = []
  var packageSwiftMentions = 0
  var pbxprojMentions = 0
  var dependencyMarkers: [String] = []
  var embeddedSDKBundles: [String] = []
  var keychainFiles: [String] = []
  var atsFiles: [String] = []
  var preferencesBundles: [String] = []
  var otherRequiredReasonFiles: [String] = []
  var skippedSensitivePaths: [String] = []

  while let item = enumerator.nextObject() as? URL {
    let name = item.lastPathComponent
    let values = try item.resourceValues(forKeys: [.isDirectoryKey])
    if values.isDirectory == true {
      if skippedDirectories.contains(name) {
        enumerator.skipDescendants()
        continue
      }
      if name.hasSuffix(".xcframework") {
        embeddedSDKBundles.append(relativePath(from: root, item))
        enumerator.skipDescendants()
      }
      if name == "Settings.bundle" {
        preferencesBundles.append(relativePath(from: root, item))
      }
      continue
    }
    if isSensitivePath(name) {
      skippedSensitivePaths.append(relativePath(from: root, item))
      continue
    }

    let relative = relativePath(from: root, item)
    if name == "Package.swift" && relative == "Package.swift" {
      let text = try String(contentsOf: item, encoding: .utf8)
      packageSwiftMentions = occurrenceCount(text, "PrivacyInfo.xcprivacy")
      if text.contains(".package(") {
        dependencyMarkers.append("Package.swift .package(")
      }
      if text.contains(".binaryTarget") {
        dependencyMarkers.append("Package.swift .binaryTarget")
      }
      continue
    }
    if name.hasSuffix(".pbxproj") {
      let text = try String(contentsOf: item, encoding: .utf8)
      pbxprojMentions += pbxprojResourcePhaseMentions(text)
      continue
    }
    if name == "PrivacyInfo.xcprivacy" {
      let data = try Data(contentsOf: item)
      manifestPaths.append(relative)
      manifests.append(parsePrivacyManifest(data))
      continue
    }

    let isSwift = name.hasSuffix(".swift")
    let isPlist = name.hasSuffix(".plist") || name.hasSuffix(".entitlements")
    if !isSwift && !isPlist {
      continue
    }
    let text = try String(contentsOf: item, encoding: .utf8)
    if isSwift && relative.hasPrefix("Sources/") {
      librarySources.append(text)
    } else if isSwift && relative.hasPrefix("Examples/") {
      exampleSources.append(text)
    }
    let scanned = isSwift ? sourceForAPIScan(text) : text
    if keychainTokens.contains(where: { containsIdentifier(scanned, $0) }) {
      keychainFiles.append(relative)
    }
    if atsTokens.contains(where: { containsIdentifier(scanned, $0) || scanned.contains($0) }) {
      atsFiles.append(relative)
    }
    if otherRequiredReasonTokens.contains(where: { containsIdentifier(scanned, $0) }) {
      if isSwift && (relative.hasPrefix("Sources/") || relative.hasPrefix("Examples/")) {
        otherRequiredReasonFiles.append(relative)
      }
    }
  }

  manifestPaths.sort()
  return RepositoryPrivacyAudit(
    libraryUse: mergeUses(librarySources.map(classifyUserDefaultsUse)),
    exampleUse: mergeUses(exampleSources.map(classifyUserDefaultsUse)),
    manifestPaths: manifestPaths,
    manifests: manifests,
    packageSwiftMentions: packageSwiftMentions,
    pbxprojResourcePhaseMentions: pbxprojMentions,
    dependencyMarkers: dependencyMarkers,
    embeddedSDKBundles: embeddedSDKBundles.sorted(),
    keychainFiles: keychainFiles.sorted(),
    atsFiles: atsFiles.sorted(),
    preferencesBundles: preferencesBundles.sorted(),
    otherRequiredReasonFiles: otherRequiredReasonFiles.sorted(),
    skippedSensitivePaths: skippedSensitivePaths.sorted()
  )
}

private func occurrenceCount(_ text: String, _ needle: String) -> Int {
  var count = 0
  var search = text.startIndex
  while let found = text.range(of: needle, range: search..<text.endIndex) {
    count += 1
    search = found.upperBound
  }
  return count
}

private struct ScanError: Error, CustomStringConvertible {
  var description: String
  init(_ description: String) { self.description = description }
}

private func plist(_ xml: String) -> Data {
  Data(xml.utf8)
}

private let validCA921Manifest = """
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
    <key>NSPrivacyTracking</key>
    <false/>
    <key>NSPrivacyAccessedAPITypes</key>
    <array>
      <dict>
        <key>NSPrivacyAccessedAPIType</key>
        <string>NSPrivacyAccessedAPICategoryUserDefaults</string>
        <key>NSPrivacyAccessedAPITypeReasons</key>
        <array>
          <string>CA92.1</string>
        </array>
      </dict>
    </array>
  </dict>
  </plist>
  """

// MARK: - Tests

@Suite("Static UserDefaults privacy audit")
struct PrivacyManifestAuditTests {

  @Test("Comments and string literals are not UserDefaults use")
  func ignoresCommentsAndStrings() {
    let source = """
      // UserDefaults.standard.set(true, forKey: "remember")
      let note = "NVRStore and @AppStorage are names, not calls"
      /* CFPreferencesCopyAppValue */
      let host = "camera.local"
      """
    #expect(classifyUserDefaultsUse(source: source) == .none)
  }

  @Test("UserDefaults.standard is app-private and matches CA92.1 exactly once")
  func standardDefaultsMatchCA921() {
    let source = """
      let store = UserDefaults.standard
      store.set(false, forKey: "muted")
      """
    #expect(classifyUserDefaultsUse(source: source) == .appPrivate)
    let parsed = parsePrivacyManifest(plist(validCA921Manifest))
    #expect(parsed.isValidPlist)
    #expect(ca921Decision(use: .appPrivate, manifests: [parsed]) == .declareSingleCA921)
    #expect(
      includedOnce(
        decision: .declareSingleCA921,
        manifestPaths: [sdkPrivacyManifestPath],
        packageSwiftMentions: 0,
        pbxprojResourcePhaseMentions: 0
      )
    )
  }

  @Test("A nil suite is the app container")
  func nilSuiteIsAppPrivate() {
    let source = "let store = UserDefaults(suiteName: nil)"
    #expect(classifyUserDefaultsUse(source: source) == .appPrivate)
  }

  @Test("A named suite does not match CA92.1")
  func namedSuiteDoesNotMatch() {
    let source = "let store = UserDefaults(suiteName: \"group.example.cameras\")"
    #expect(classifyUserDefaultsUse(source: source) == .suiteOrAppGroup)
    let parsed = parsePrivacyManifest(plist(validCA921Manifest))
    let decision = ca921Decision(use: .suiteOrAppGroup, manifests: [parsed])
    #expect(
      decision
        == .refuse("App Group or named-suite UserDefaults does not match CA92.1")
    )
    let omitted = ca921Decision(use: .suiteOrAppGroup, manifests: [])
    #expect(omitted != .declareSingleCA921)
  }

  @Test("@AppStorage without a custom store matches CA92.1; a custom store does not")
  func appStorageStoreArgument() {
    let plain = "@AppStorage(\"muted\") var muted = false"
    #expect(classifyUserDefaultsUse(source: plain) == .appPrivate)
    let custom =
      "@AppStorage(\"muted\", store: UserDefaults(suiteName: \"group.example\")) var muted = false"
    #expect(classifyUserDefaultsUse(source: custom) == .suiteOrAppGroup)
    let standardStore =
      "@AppStorage(\"muted\", store: UserDefaults.standard) var muted = false"
    #expect(classifyUserDefaultsUse(source: standardStore) == .appPrivate)
  }

  @Test("NVRStore without a defaults API is not CA92.1 use")
  func nvrStoreNameAloneIsNotDefaultsUse() {
    let source = """
      struct NVRStore {
        var savedHost: String?
      }
      """
    #expect(classifyUserDefaultsUse(source: source) == .none)
  }

  @Test("NVRStore is not treated as CA92.1")
  func nvrStoreIsUnclassified() {
    let source = """
      struct NVRStore {
        func save() { UserDefaults.standard.set(true, forKey: "on") }
      }
      """
    #expect(classifyUserDefaultsUse(source: source) == .unclassifiedWrapper)
    let parsed = parsePrivacyManifest(plist(validCA921Manifest))
    let decision = ca921Decision(use: .unclassifiedWrapper, manifests: [parsed])
    #expect(
      decision
        == .refuse("NVRStore is not app-private UserDefaults use, so CA92.1 does not match")
    )
  }

  @Test("No call sites means the declaration is omitted")
  func noUseOmitsDeclaration() {
    #expect(ca921Decision(use: .none, manifests: []) == .omit)
    let parsed = parsePrivacyManifest(plist(validCA921Manifest))
    #expect(
      ca921Decision(use: .none, manifests: [parsed])
        == .refuse(
          "UserDefaults reason [\"CA92.1\"] is declared but no app-private UserDefaults call exists"
        )
    )
    #expect(
      includedOnce(
        decision: .omit,
        manifestPaths: [],
        packageSwiftMentions: 0,
        pbxprojResourcePhaseMentions: 0
      )
    )
  }

  @Test("Duplicate manifest copies and invalid plists are rejected")
  func rejectsDuplicatesAndInvalidPlists() {
    let project = """
      /* Begin PBXFileReference section */
      F1 /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; };
      /* End PBXFileReference section */
      /* Begin PBXResourcesBuildPhase section */
      X1 = { isa = PBXResourcesBuildPhase; files = ( A1 /* PrivacyInfo.xcprivacy in Resources */, ); };
      X2 = { isa = PBXResourcesBuildPhase; files = ( A2 /* PrivacyInfo.xcprivacy in Resources */, ); };
      /* End PBXResourcesBuildPhase section */
      """
    #expect(pbxprojResourcePhaseMentions(project) == 2)
    #expect(
      includedOnce(
        decision: .declareSingleCA921,
        manifestPaths: [sdkPrivacyManifestPath],
        packageSwiftMentions: 1,
        pbxprojResourcePhaseMentions: 0
      ) == false
    )
    let invalid = parsePrivacyManifest(Data("not a plist".utf8))
    #expect(invalid.isValidPlist == false)
    #expect(
      ca921Decision(use: .appPrivate, manifests: [invalid])
        == .refuse("A PrivacyInfo.xcprivacy file is not a valid property list")
    )
  }

  @Test("Interpolation is code and a file-reference outside Resources is not a copy")
  func interpolationAndFileReference() {
    let source = "let label = \"store is \\(UserDefaults.standard)\""
    #expect(classifyUserDefaultsUse(source: source) == .appPrivate)
    let project = """
      /* Begin PBXFileReference section */
      F1 /* PrivacyInfo.xcprivacy */ = {isa = PBXFileReference; path = PrivacyInfo.xcprivacy; };
      /* End PBXFileReference section */
      /* Begin PBXResourcesBuildPhase section */
      X1 = { isa = PBXResourcesBuildPhase; files = ( A1 /* Assets.xcassets in Resources */, ); };
      /* End PBXResourcesBuildPhase section */
      """
    #expect(pbxprojResourcePhaseMentions(project) == 0)
  }

  @Test("IPCamKit has no app-private UserDefaults use, so CA92.1 stays undeclared")
  func repositoryOmitsCA921() throws {
    let root = repositoryRoot()
    let package = root.appendingPathComponent("Package.swift")
    let packageText = try String(contentsOf: package, encoding: .utf8)
    #expect(packageText.contains("name: \"IPCamKit\""))
    let audit = try scanRepository(root: root)
    #expect(audit.skippedSensitivePaths.isEmpty)
    #expect(audit.libraryUse == .none)
    #expect(audit.exampleUse == .none)
    #expect(audit.dependencyMarkers.isEmpty)
    #expect(audit.embeddedSDKBundles.isEmpty)
    let decision = ca921Decision(use: audit.libraryUse, manifests: audit.manifests)
    #expect(decision == .omit)
    #expect(
      includedOnce(
        decision: decision,
        manifestPaths: audit.manifestPaths,
        packageSwiftMentions: audit.packageSwiftMentions,
        pbxprojResourcePhaseMentions: audit.pbxprojResourcePhaseMentions
      )
    )
    #expect(audit.pbxprojResourcePhaseMentions == 0)
    #expect(audit.keychainFiles.isEmpty)
    #expect(audit.atsFiles.isEmpty)
    #expect(audit.preferencesBundles.isEmpty)
    #expect(audit.otherRequiredReasonFiles.isEmpty)
  }
}
