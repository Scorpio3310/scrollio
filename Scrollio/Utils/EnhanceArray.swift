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
    /// The keys that are paths with a symbolic link in them, by where the links lead:
    /// `/Applications/Safari.app`, as "Choose in Finder…" stores it, is a link into the
    /// system's cryptex, and the running Safari reports the path behind it. Read from disk
    /// when the array changes, never at a lookup (the scroll path looks an app up for
    /// every wheel event). What is stored stays as it is.
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
                    if let resolved = Self.pathBehindSymbolicLinks(of: targetPropertyValue) {
                        nextResolved[resolved] = index
                    }
                    break
                }
            }
        }
        dictionary = nextDic
        dictionaryOfResolvedPaths = nextResolved
    }
    /// Where the symbolic links in `key` lead, when it is an absolute path and they lead
    /// somewhere else; nil for every other key (a path without a link, a file that is not
    /// there, a key that is no path).
    static func pathBehindSymbolicLinks(of key: String) -> String? {
        guard key.hasPrefix("/") else { return nil }
        let resolved = (key as NSString).resolvingSymlinksInPath
        return resolved == key ? nil : resolved
    }
}
