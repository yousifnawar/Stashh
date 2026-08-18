import Foundation
import AppKit
import UniformTypeIdentifiers

/// Collects everything in a drag — several files at once, or images dragged
/// straight out of a browser with no file behind them.
enum DropIngest {

    /// Types our drop targets advertise.
    static let acceptedTypes: [UTType] = [.fileURL, .image]

    enum Payload {
        case file(URL)
        case imageData(Data, name: String)
    }

    /// Loads every provider in parallel but hands the results back in the order
    /// they were dropped. Providers resolve on arbitrary queues, so the partial
    /// results are kept behind a lock rather than appended to a shared array.
    static func collect(_ providers: [NSItemProvider],
                        completion: @escaping ([Payload]) -> Void) {
        let lock = NSLock()
        var byIndex: [Int: Payload] = [:]
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            load(provider) { payload in
                if let payload {
                    lock.lock()
                    byIndex[index] = payload
                    lock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(byIndex.sorted { $0.key < $1.key }.map(\.value))
        }
    }

    private static func load(_ provider: NSItemProvider, done: @escaping (Payload?) -> Void) {
        // A real file on disk is always the better payload — keep the original.
        if provider.canLoadObject(ofClass: URL.self) {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    done(.file(url))
                } else {
                    loadImageData(provider, done: done)
                }
            }
            return
        }
        loadImageData(provider, done: done)
    }

    private static func loadImageData(_ provider: NSItemProvider, done: @escaping (Payload?) -> Void) {
        let imageType = provider.registeredTypeIdentifiers.first {
            UTType($0)?.conforms(to: .image) == true
        }
        guard let imageType else { done(nil); return }

        provider.loadDataRepresentation(forTypeIdentifier: imageType) { data, _ in
            guard let data, NSImage(data: data) != nil else { done(nil); return }
            let name = provider.suggestedName ?? "Dropped image"
            done(.imageData(data, name: name))
        }
    }
}
