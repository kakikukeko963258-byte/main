import XCTest
import CoreImage

final class RawCameraTests: XCTestCase {
    func testDNGDevelopsAndAdjustmentsChangePixels() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Synthetic", withExtension: "dng"))
        var neutral = RawAdjustments()
        neutral.look = "Neutral"; neutral.grain = 0
        let first = try RawDeveloper.image(url, adjustments: neutral)
        XCTAssertEqual(first.extent.width, 256)
        XCTAssertEqual(first.extent.height, 192)
        let original = try RawDeveloper.jpeg(first)
        var changed = neutral; changed.exposure = 1.5; changed.look = "Cinema"; changed.grain = 0.4
        let developed = try RawDeveloper.jpeg(RawDeveloper.image(url, adjustments: changed))
        XCTAssertGreaterThan(original.count, 500)
        XCTAssertNotEqual(original, developed)
        XCTAssertEqual(try RawDeveloper.jpeg(RawDeveloper.image(url, adjustments: changed)), developed,
                       "Grain must remain stable between identical renders")
        let reduced = try RawDeveloper.image(url, adjustments: neutral, maxSide: 128)
        XCTAssertLessThanOrEqual(max(reduced.extent.width, reduced.extent.height), 130)
    }

    func testOriginalSurvivesEditingAndDNGExport() throws {
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Synthetic", withExtension: "dng"))
        let data = try Data(contentsOf: fixture)
        let library = RawPhotoLibrary()
        let added = expectation(description: "RAW stored and developed")
        library.add(data: data, format: "RAW") { added.fulfill() }
        wait(for: [added], timeout: 30)
        let shot = try XCTUnwrap(library.shots.first)
        defer {
            for suffix in ["dng", "json", "jpg"] {
                try? FileManager.default.removeItem(at: library.root.appendingPathComponent(shot.stem + "." + suffix))
            }
        }
        XCTAssertEqual(try Data(contentsOf: library.original(shot)), data)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.thumbnail(shot).path))
        var settings = shot.adjustments; settings.exposure = -0.5; settings.look = "Mono"
        library.save(shot, adjustments: settings)
        // Both work and its main-queue publication must complete before checking reload.
        let saved = expectation(description: "Edit saved")
        library.queue.async { DispatchQueue.main.async { saved.fulfill() } }
        wait(for: [saved], timeout: 30)
        XCTAssertNil(library.error)
        let reloaded = try XCTUnwrap(RawPhotoLibrary().shots.first(where: { $0.id == shot.id }))
        XCTAssertEqual(reloaded.adjustments, settings)
        XCTAssertEqual(try Data(contentsOf: library.original(shot)), data)
        let exported = expectation(description: "DNG export")
        library.export(reloaded, kind: "DNG") { url in
            do {
                let url = try XCTUnwrap(url)
                XCTAssertEqual(try Data(contentsOf: url), data)
                try FileManager.default.removeItem(at: url)
            } catch { XCTFail(error.localizedDescription) }
            exported.fulfill()
        }
        wait(for: [exported], timeout: 30)
        let jpeg = expectation(description: "JPEG export")
        library.export(reloaded, kind: "JPEG") { url in
            if let url {
                XCTAssertNotNil(UIImage(contentsOfFile: url.path))
                try? FileManager.default.removeItem(at: url)
            } else { XCTFail(library.error ?? "Missing JPEG") }
            jpeg.fulfill()
        }
        wait(for: [jpeg], timeout: 30)
    }

    func testInvalidRawReportsDevelopmentErrorButKeepsOriginal() throws {
        let library = RawPhotoLibrary()
        let data = Data("invalid RAW fixture".utf8)
        let finished = expectation(description: "Invalid RAW handled")
        library.add(data: data, format: "RAW") { finished.fulfill() }
        wait(for: [finished], timeout: 20)
        let shot = try XCTUnwrap(library.shots.first)
        defer {
            for suffix in ["dng", "json", "jpg"] {
                try? FileManager.default.removeItem(at: library.root.appendingPathComponent(shot.stem + "." + suffix))
            }
        }
        XCTAssertNotNil(library.error)
        XCTAssertEqual(try Data(contentsOf: library.original(shot)), data)
    }
}
