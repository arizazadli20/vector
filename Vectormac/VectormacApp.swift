//
//  VectormacApp.swift
//  Vectormac
//
//  Created by ARIZ AZADOV on 28/03/26.
//

import SwiftUI

@main
struct VectormacApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
