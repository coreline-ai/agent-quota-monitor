import Darwin
import Foundation
import XCTest
@testable import AIQuotaMonitor

final class CodexRuntimeLocatorTests: XCTestCase {
    func testExplicitPathWinsOverPathAndResolvesNodeShebang() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let explicitDirectory = root.appending(path: "explicit")
        let pathDirectory = root.appending(path: "path")
        try FileManager.default.createDirectory(at: explicitDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: pathDirectory, withIntermediateDirectories: true)
        let explicit = explicitDirectory.appending(path: "codex")
        let node = explicitDirectory.appending(path: "node")
        try makeExecutable("#!/usr/bin/env node\n", at: explicit)
        try makeExecutable("#!/bin/sh\n", at: node)
        let pathCodex = pathDirectory.appending(path: "codex")
        try makeExecutable("#!/bin/sh\n", at: pathCodex)

        let runtime = CodexRuntimeLocator(
            homeURL: root,
            path: pathDirectory.path
        ).locate(explicitURL: explicit)

        XCTAssertEqual(runtime?.source, .explicit)
        XCTAssertEqual(runtime?.executableURL, explicit.standardizedFileURL)
        XCTAssertEqual(runtime?.runtimeURL, node.standardizedFileURL)
    }

    func testFindsNewestNVMVersionWhenGUIPathIsEmpty() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let versions = root.appending(path: ".nvm/versions/node")
        let old = versions.appending(path: "v20.0.0/bin")
        let newest = versions.appending(path: "v22.0.0/bin")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newest, withIntermediateDirectories: true)
        try makeExecutable("#!/bin/sh\n", at: old.appending(path: "codex"))
        try makeExecutable("#!/bin/sh\n", at: newest.appending(path: "codex"))

        let runtime = CodexRuntimeLocator(homeURL: root, path: "").locate()

        XCTAssertEqual(runtime?.source, .nodeManager)
        XCTAssertEqual(runtime?.executableURL, newest.appending(path: "codex").standardizedFileURL)
    }

    func testFindsBundledCodexCLIAfterKnownUserLocations() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appending(path: "Codex.app")
        let resources = bundle.appending(path: "Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let executable = resources.appending(path: "codex")
        try makeExecutable("#!/bin/sh\n", at: executable)

        let runtime = CodexRuntimeLocator(
            homeURL: root,
            path: "",
            applicationRoots: [bundle]
        ).locate()

        XCTAssertEqual(runtime?.source, .applicationBundle)
        XCTAssertEqual(runtime?.executableURL, executable.standardizedFileURL)
    }

    func testFindsVoltaAndMiseCandidatesWithoutShellEvaluation() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let volta = root.appending(path: ".volta/bin/codex")
        try makeExecutable("#!/bin/sh\n", at: volta)
        let voltaRuntime = CodexRuntimeLocator(homeURL: root, path: "").locate()
        XCTAssertEqual(voltaRuntime?.executableURL, volta.standardizedFileURL)

        try? FileManager.default.removeItem(at: volta)
        let mise = root.appending(path: ".local/share/mise/shims/codex")
        try makeExecutable("#!/bin/sh\n", at: mise)
        let miseRuntime = CodexRuntimeLocator(homeURL: root, path: "").locate()
        XCTAssertEqual(miseRuntime?.executableURL, mise.standardizedFileURL)
    }

    func testReturnsNilWhenNoCandidateIsExecutable() throws {
        let root = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        XCTAssertNil(CodexRuntimeLocator(homeURL: root, path: "", applicationRoots: []).locate())
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeExecutable(_ contents: String, at url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
        XCTAssertEqual(chmod(url.path, 0o700), 0)
    }
}
