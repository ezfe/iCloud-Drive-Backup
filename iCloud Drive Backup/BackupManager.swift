//
//  BackupManager.swift
//  iCloud Drive Backup
//
//  Created by Ezekiel Elin on 8/27/22.
//

import Foundation
import DequeModule

extension URL {
	var isDirectory: Bool {
		(try? resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
	}
	
	var isCloud: Bool {
		return self.lastPathComponent.hasSuffix(".icloud")
	}
}

struct FinderCloudData: Decodable, Equatable, Hashable {
	let NSURLNameKey: String
	let NSURLFileSizeKey: Int
}

struct CloudTracker: Equatable, Hashable {
	let downloadedUrl: URL
	var lastRequestedDownload: Date?
}

enum CloudStatus: Equatable, Hashable {
	case notCloud
	case cloud(CloudTracker)
}

struct BackupJob: Hashable, Equatable {
	let source: URL
	let destination: URL
	
	let directory: Bool
	var cloudStatus: CloudStatus
	
	init(source: URL, destinationFolder: URL) {
		let fileName = source.lastPathComponent
		
		self.source = source
		if !source.isDirectory && fileName.hasPrefix(".") && fileName.hasSuffix(".icloud") {
			let data = try! Data(contentsOf: source)
			let decoder = PropertyListDecoder()
			let cloudInfo = try! decoder.decode(FinderCloudData.self, from: data)
			let downloadedItem = source.deletingLastPathComponent().appendingPathComponent(cloudInfo.NSURLNameKey)
			let cloudTracker = CloudTracker(downloadedUrl: downloadedItem)
			
			self.destination = destinationFolder.appendingPathComponent(cloudInfo.NSURLNameKey)
			self.directory = false
			self.cloudStatus = .cloud(cloudTracker)
		} else {
			self.destination = destinationFolder.appendingPathComponent(fileName)
			self.directory = source.isDirectory
			self.cloudStatus = .notCloud
		}
	}
}

actor BackupManager {
	/// iCloud files that need to be processed
	var delayedFiles = 0
	var queuedFiles = Deque<BackupJob>()
	
	let source: URL
	let destination: URL
	
	init(source: URL, destination: URL) {
		self.source = source
		self.destination = destination
		
		let fm = FileManager.default
		assert(source.isDirectory)
		if fm.fileExists(atPath: destination.path) {
			try! fm.removeItem(at: destination)
		}
		try! fm.createDirectory(at: destination, withIntermediateDirectories: true)
	}
	
	// MARK: - Queue
	
	func queue(item: BackupJob) {
		guard item.source.lastPathComponent != ".DS_Store" else {
			return
		}
		self.queuedFiles.append(item)
	}
	
	func isEmpy() -> Bool {
		return queuedFiles.isEmpty && delayedFiles == 0
	}
	
	func queue(item: BackupJob, delay: UInt64) async {
		guard item.source.lastPathComponent != ".DS_Store" else {
			return
		}
		delayedFiles += 1
		Task {
			print("Reprocessing in \(delay)s : \(item)")
			try! await Task.sleep(nanoseconds: 1_000_000_000 * delay)
			queuedFiles.append(item)
			print("Re-queued")
			delayedFiles -= 1
		}
	}
	
	// MARK: Routine
	
	func backup(progress: (Int, Int, Int) -> Void) async {
		print("Starting backup...")
		
		let items = try! FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)

		// Build initial queue...
		for item in items {
			queue(item: BackupJob(source: item, destinationFolder: destination))
		}
		
		await planLoop(progress: progress)
	}
	
	func planLoop(progress: (Int, Int, Int) -> Void) async {
		let fm = FileManager.default

		var total = queuedFiles.count
		while !isEmpy() {
			progress(queuedFiles.count, delayedFiles, total)
			guard let item = queuedFiles.popFirst() else {
				try! await Task.sleep(nanoseconds: 500_000_000) // 1/2 second
				continue
			}

			switch item.cloudStatus {
				case .cloud(let cloudTracker):
					if fm.fileExists(atPath: cloudTracker.downloadedUrl.path) {
						try! fm.copyItem(at: cloudTracker.downloadedUrl, to: item.destination)
					} else if shouldRequestDownload(tracker: cloudTracker) {
						print("Requesting download of \(cloudTracker.downloadedUrl.path)")
						try! fm.startDownloadingUbiquitousItem(at: item.source)
						var newItem = item
						var newTracker = cloudTracker
						newTracker.lastRequestedDownload = Date()
						newItem.cloudStatus = .cloud(newTracker)
						await queue(item: newItem, delay: UInt64.random(in: 8...12))
					} else {
						// Re-process in 10 seconds
						await queue(item: item, delay: UInt64.random(in: 1...10))
					}
				case .notCloud:
					if item.directory {
						if fm.fileExists(atPath: item.destination.path) {
							try! fm.removeItem(at: item.destination)
						}
						try! fm.createDirectory(at: item.destination, withIntermediateDirectories: true)

						let subItems = try! fm.contentsOfDirectory(at: item.source, includingPropertiesForKeys: nil)
						total += subItems.count

						for subItem in subItems {
							queue(item: BackupJob(source: subItem, destinationFolder: item.destination))
						}
					} else {
						do {
							
							try fm.copyItem(at: item.source, to: item.destination)
						} catch {
							print("Failed to copy \(item.source.path) to \(item.destination.path)")
						}
					}
			}
		}
		print("Complete...")
	}
	
	func shouldRequestDownload(tracker: CloudTracker) -> Bool {
		if let lastRequestedDate = tracker.lastRequestedDownload {
			let now = Date()
			let interval = now.timeIntervalSince(lastRequestedDate)
			return interval > 300 // 5 minutes
		} else {
			return true
		}
	}
}
