//
//  ContentView.swift
//  iCloud Drive Backup
//
//  Created by Ezekiel Elin on 8/27/22.
//

import SwiftUI

struct ContentView: View {
	@State
	var isBackingUp = false
	@State
	var queuedFiles: Int = 0
	@State
	var waitingFiles: Int = 0
	@State
	var total: Int = 0
	@State
	var backupManager: BackupManager?
	
	var body: some View {
		VStack {
			if isBackingUp {
				Text("Found \(total) files")
				Text("In Queue: \(queuedFiles)")
				Text("iCloud Downloading: \(waitingFiles)")
				ProgressView(value: Double(total - queuedFiles - waitingFiles), total: Double(total))
			}
			Button {
				self.backup()
			} label: {
				Label("Start Backup", systemImage: "doc.on.doc")
			}
		}
		.padding()
	}
	
	func backup() {
		self.isBackingUp = true
//		let source = URL(fileURLWithPath: "/Users/ezekielelin/Library/Mobile Documents/com~apple~CloudDocs")
//		let destination = URL(fileURLWithPath: "/Volumes/1TB SSD Storage/iCloud Drive Backup")
//		let source = URL(fileURLWithPath: "/Users/ezekielelin/Desktop")
//		let destination = URL(fileURLWithPath: "/Volumes/1TB SSD Storage/iCloud Desktop Backup")
		let source = URL(fileURLWithPath: "/Users/ezekielelin/Documents")
		let destination = URL(fileURLWithPath: "/Volumes/1TB SSD Storage/iCloud Documents Backup")

		let manager = BackupManager(source: source, destination: destination)
		Task {
			await manager.backup { queued, delayed, total in
				self.queuedFiles = queued
				self.waitingFiles = delayed
				self.total = total
			}
			self.isBackingUp = false
		}
		self.backupManager = manager
	}
}

struct ContentView_Previews: PreviewProvider {
	static var previews: some View {
		ContentView()
	}
}
