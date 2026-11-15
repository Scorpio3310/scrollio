//
//  EnhanceArray.swift
//  Mos
//  增强数组, 使用内置字典便于快速查找
//  Created by Caldis on 2019/3/27.
//  Copyright © 2019 Caldis. All rights reserved.
//

import Foundation

class EnhanceArray<T:Codable> {

    private var array: [T]! {
        didSet {
            updateDictionary()
            observer()
        }
    }
    private var dictionary = [String: Int]()
    /// The keys that are paths with a symbolic link in them, by where the links lead
    /// (`StoredPathLinks`): `/Applications/Safari.app`, as "Choose in Finder…" stores it,
    /// is a link into the system's cryptex, and the running Safari reports the path behind
    /// it. Read from disk when the array changes, never at a lookup (the scroll path looks
    /// an app up for every wheel event). What is stored stays as it is.
    private var dictionaryOfResolvedPaths = [String: Int]()
    private var dictionaryKey: String!
    private var observer = {()}

    public init(withArray targetArray: [T] = [], matchKey targetDictionaryKey: String = "identity", forObserver observerHandler: @escaping ()->Void = {()}) {
        setInitData(targetDictionaryKey, targetArray)
        observer = observerHandler
    }
    public init(withData targetData: Data, matchKey targetDictionaryKey: String = "identity", forObserver observerHandler: @escaping ()->Void = {()}) throws {
        let decoder = JSONDecoder()
        let targetArray = try decoder.decode([T].self, from: targetData)
        setInitData(targetDictionaryKey, targetArray)
        observer = observerHandler
    }
}

/**
 * 接口
 **/
extension EnhanceArray {
    // 属性
    var count: Int {
        get {
            return array.count
        }
    }
    // 获取值
    /// The item stored under `key`. A path also finds the item whose stored path leads to
    /// it through symbolic links; the item stored under the key itself always comes first.
    public func get(by key: String?) -> T? {
        guard let validKey = key else { return nil }
        if let index = dictionary[validKey] {
            return array[index]
        }
        guard !dictionaryOfResolvedPaths.isEmpty, let index = dictionaryOfResolvedPaths[validKey] else { return nil }
        return array[index]
    }
    public func get(by index: Int?) -> T? {
        guard let validIndex = index else { return nil }
        return array[validIndex]
    }
    // 更新值
    public func set(by key: String, of item: T) -> EnhanceArray {
        if let index = dictionary[key] {
            array[index] = item
        }
        return self
    }
    public func set(by index: Int, of item: T) -> EnhanceArray {
        array[index] = item
        return self
    }
    public func append(_ item: T) {
        array.append(item)
    }
    /// Puts `item` at `index` (clamped to the array), e.g. to undo a removal.
    public func insert(_ item: T, at index: Int) {
        array.insert(item, at: min(max(0, index), array.count))
    }
    // 删除值
    public func remove(from key: String) {
        if let index = dictionary[key] {
            array.remove(at: index)
        }
    }
    public func remove(at index: Int) {
        array.remove(at: index)
    }
    // 获取 JSON 数据
    public func json() -> Data? {
        let encoder = JSONEncoder()
        do {
            return try encoder.encode(array)
        } catch {
            AppSystemLog.problem("Settings: a list could not be written as JSON (\(type(of: error)))")
            return nil
        }
    }
    // 更新内部数据
    public func update() {
        updateDictionary()
    }
}

/**
 * 工具
 **/
extension EnhanceArray {
    // 为了触发 didSet
    // 直接在 init 处初始化不会调用 didSet
    private func setInitData(_ targetDictionaryKey: String, _ targetArray: [T]) {
        dictionaryKey = targetDictionaryKey
        array = targetArray
    }
    // 更新
    private func updateDictionary() {
        var nextDic = [String: Int]()
        var nextResolved = [String: Int]()
        for (index, item) in array.enumerated() {
            let mirror = Mirror(reflecting: item)
            for property in mirror.children {
                if let targetPropertyKey = property.label, targetPropertyKey == dictionaryKey {
                    guard let targetPropertyValue = property.value as? String else {
                        fatalError("Property of \(String(describing: dictionaryKey)) in EnhanceArray must be String Type")
                    }
                    nextDic[targetPropertyValue] = index
                    for form in StoredPathLinks.forms(of: targetPropertyValue) {
                        nextResolved[form] = index
                    }
                    break
                }
            }
        }
        dictionary = nextDic
        dictionaryOfResolvedPaths = nextResolved
    }
}

/// Where the symbolic links in a stored path lead: the other paths under which the item
/// stored at it is found (`EnhanceArray.get(by:)`).
///
/// `/Applications/Safari.app` is a link to `../System/Cryptexes/App/System/Applications/
/// Safari.app`, and `/System/Cryptexes/App` is a link into `/System/Volumes/Preboot`; the
/// running Safari reports the path at the end. Every path on the way counts.
///
/// Only the links themselves are read (`readlink`, one folder name at a time), and only
/// while the path is inside the folders that may be looked into
/// (`ScrollUtils.mayLookIntoBundle`: the Applications folders and /System). Nothing is asked
/// about a path on another volume, on a network share or in a folder macOS guards with a
/// prompt, also not where a link leads there: this runs at launch and when a settings file
/// is imported, on the main thread, with whatever paths the list holds.
enum StoredPathLinks {

    /// Which paths may be looked at on disk. A seam: tests point it at a temporary folder.
    static var mayLookAt: (String) -> Bool = { ScrollUtils.mayLookIntoBundle(atPath: $0) }

    /// The paths `path` leads to through its symbolic links, nearest first. None for a path
    /// without a link, for a file that is not there, for a key that is no path and for a
    /// path that may not be looked at.
    static func forms(of path: String) -> [String] {
        var forms: [String] = []
        var current = path
        // (A chain longer than this is a loop.)
        for _ in 0..<8 {
            guard mayLookAt(current), let next = followingFirstLink(in: current),
                  next != path, !forms.contains(next) else { break }
            forms.append(next)
            current = next
        }
        return forms
    }

    /// `path` with its first symbolic link replaced by what the link points to; nil when
    /// no part of it is a link, and for a link that cannot be followed by its text alone
    /// (a ".." after a name, which may itself be a link).
    static func followingFirstLink(in path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        let parts = path.split(separator: "/").map(String.init)
        for index in parts.indices {
            let prefix = "/" + parts[...index].joined(separator: "/")
            guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: prefix) else { continue }
            // The folders before the link hold no link, so the ".." a relative link starts
            // with climb them as written.
            var base = destination.hasPrefix("/") ? [] : Array(parts[..<index])
            var target = destination.split(separator: "/").map(String.init)
            while let first = target.first, first == ".." || first == "." {
                if first == ".." {
                    guard !base.isEmpty else { return nil }
                    base.removeLast()
                }
                target.removeFirst()
            }
            guard !target.isEmpty, !target.contains(".."), !target.contains(".") else { return nil }
            let rest = Array(parts[(index + 1)...])
            return "/" + (base + target + rest).joined(separator: "/")
        }
        return nil
    }
}
