//
//  CKEncoderKeyedContainer.swift
//  NestedCloudKitCodable
//
//  Created by Guilherme Girotto on 18/11/18.
//  Copyright © 2018 Guilherme Girotto. All rights reserved.
//

import CloudKit
import Foundation

internal class CKEncoderKeyedContainer<Key>: CKKeyedEncoder where Key: CodingKey {
    
    private let object: CKEncodable
    private let zoneID: CKRecordZone.ID?
    var codingPath: [CodingKey]
    private var createdRecords: BoxedArray<CKRecord>
    
    fileprivate var storage: [String: CKRecordValue] = [:]
    
    init(object: CKEncodable,
         zoneID: CKRecordZone.ID?,
         codingPath: [CodingKey],
         createdRecords: BoxedArray<CKRecord>) {
        self.object = object
        self.zoneID = zoneID
        self.codingPath = codingPath
        self.createdRecords = createdRecords
    }
}

extension CKEncoderKeyedContainer {
    
    var recordID: CKRecord.ID {
        let normalizedZone = zoneID ?? CKRecordZone.ID(zoneName: CKRecordZone.ID.defaultZoneName, ownerName: CKCurrentUserDefaultName)
        return CKRecord.ID(recordName: object.id, zoneID: normalizedZone)
    }
    
    var generatedRecord: CKRecord {
        let output = CKRecord(recordType: object.cloudKitRecordType, recordID: recordID)
        
        for (key, value) in storage {
            output[key] = value
        }
        
        return output
    }
}

extension CKEncoderKeyedContainer: KeyedEncodingContainerProtocol {
    
    func encodeNil(forKey key: Key) throws {
        storage[key.stringValue] = nil
    }
    
    func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
        guard !object.ignoredProperties().contains(key.stringValue) else {
            return
        }
        
        // Encode a single value
        if let singleValue = value as? CKEncodable {
            try encodeSingleValue(singleValue, forKey: key)
            return
        }
        
        // Encode a an array of values
        if let values = value as? [CKEncodable] {
            try encodeValuesSequence(originValue: value, castedValues: values, forKey: key)
            return
        }
        
        // Encode an unique primitve type
        if let ckValue = value as? CKRecordValue {
            try encodeCKRecordValue(ckValue, forKey: key)
            return
        }
        
        throw CKCodableError(.typeMismatch)
    }
    
    // MARK: Auxiliar Encode functions
    
    private func encodeSingleValue(_ value: CKEncodable, forKey key: Key) throws {
        storage[key.stringValue] = try produceReference(for: value)
        let encoder = _CloudKitRecordEncoder(object: value,
                                             zoneID: zoneID,
                                             createdRecords: createdRecords)
        try value.encode(to: encoder)
        if let generatedRecord = encoder.generatedRecord {
            createdRecords.append(generatedRecord)
        }
    }
    
    private func encodeValuesSequence<T>(originValue value: T, castedValues: [CKEncodable], forKey key: Key) throws where T: Encodable {
        var references = [CKRecord.Reference]()
        try castedValues.forEach {
            let reference = try produceReference(for: $0)
            references.append(reference)
        }
        storage[key.stringValue] = references as CKRecordValue
        let encoder = _CloudKitRecordEncoder(object: object,
                                             zoneID: zoneID,
                                             createdRecords: createdRecords)
        try value.encode(to: encoder)
    }
    
    private func encodeCKRecordValue(_ value: CKRecordValue, forKey key: Key) throws {
        
        if let data = value as? Data {
            try encodeData(data, forKey: key)
        }
        
        if let datas = value as? [Data] {
            try encodeDataArray(datas, forKey: key)
        }
        
        if let url = value as? URL {
            encodeURL(url, forKey: key)
        }
        
        if let urls = value as? [URL] {
            encodeURLArray(urls, forKey: key)
        }
        
        /**
            CLLocations are encoded as Strings, since Swift Codable protocol
            cant encode/decode this type of values. The format chosen to encode
            this values is "lat;long".
         */
        if let locationString = value as? String,
            locationString.contains(Constants.locationSeparator) {
            encodeLocation(fromString: locationString, forKey: key)
        }
        
        if let locationsStrings = value as? [String],
            let firstString = locationsStrings.first,
            firstString.contains(Constants.locationSeparator) {
            encodeLocations(fromStrings: locationsStrings, forKey: key)
        }
        
        storage[key.stringValue] = value
    }
    
    private func encodeData(_ value: Data, forKey key: Key) throws {
        let tempStr = ProcessInfo.processInfo.globallyUniqueString
        let filename = "\(tempStr)_file.bin"
        let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let fileURL = baseURL.appendingPathComponent(filename, isDirectory: false)
        try value.write(to: fileURL, options: .atomic)
        let asset = CKAsset(fileURL: fileURL)
        storage[key.stringValue] = asset
    }
    
    private func encodeDataArray(_ values: [Data], forKey key: Key) throws {
        var assets = [CKAsset]()
        for i in 0..<values.count {
            let data = values[i]
            let tempStr = ProcessInfo.processInfo.globallyUniqueString
            let filename = "\(tempStr)_file.bin"
            let baseURL = URL(fileURLWithPath: NSTemporaryDirectory())
            let fileURL = baseURL.appendingPathComponent(filename, isDirectory: false)
            try data.write(to: fileURL, options: .atomic)
            let asset = CKAsset(fileURL: fileURL)
            assets.append(asset)
        }
        storage[key.stringValue] = assets as CKRecordValue
    }
    
    private func encodeURL(_ value: URL, forKey key: Key) {
        let asset = CKAsset(fileURL: value)
        storage[key.stringValue] = asset
    }
    
    private func encodeURLArray(_ values: [URL], forKey key: Key) {
        var assets = [CKAsset]()
        for i in 0..<values.count {
            let url = values[i]
            let asset = CKAsset(fileURL: url)
            assets.append(asset)
        }
        storage[key.stringValue] = assets as CKRecordValue
    }
    
    private func encodeLocation(fromString value: String, forKey key: Key) {
        let split = value.split(separator: Constants.locationSeparator)
        
        guard let latitude = Double(split[0]),
            let longitude = Double(split[1]) else {
                storage[key.stringValue] = nil
                return
        }
        
        storage[key.stringValue] = CLLocation(latitude: latitude, longitude: longitude)
    }
    
    private func encodeLocations(fromStrings values: [String], forKey key: Key) {
        var locations = [CLLocation]()
        values.forEach {
            let split = $0.split(separator: Constants.locationSeparator)
            guard let latitude = Double(split[0]),
                let longitude = Double(split[1]) else {
                    storage[key.stringValue] = nil
                    return
            }
            let location = CLLocation(latitude: latitude, longitude: longitude)
            locations.append(location)
        }
        
        storage[key.stringValue] = locations as CKRecordValue
    }
    
    private func produceReference(for value: CKEncodable) throws -> CKRecord.Reference {
        let recordID = CKRecord.ID(recordName: value.id)
        return CKRecord.Reference(recordID: recordID, action: .deleteSelf)
    }
    
    func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let unkeyedContainer = CKEncoderUnkeyedContainer(object: object,
                                                         zoneID: zoneID,
                                                         createdRecords: createdRecords,
                                                         codingPath: codingPath)
        return unkeyedContainer
    }
    
    func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: Key) -> KeyedEncodingContainer<NestedKey> where NestedKey : CodingKey {
        let nestedKeyedContainer = CKEncoderKeyedContainer<NestedKey>(object: object,
                                                                      zoneID: zoneID,
                                                                      codingPath: codingPath,
                                                                      createdRecords: createdRecords)
        return KeyedEncodingContainer(nestedKeyedContainer)
    }
    
    func superEncoder() -> Encoder {
        return _CloudKitRecordEncoder(object: object,
                                      zoneID: zoneID,
                                      createdRecords: createdRecords)
    }
    
    func superEncoder(forKey key: Key) -> Encoder {
        return _CloudKitRecordEncoder(object: object,
                                      zoneID: zoneID,
                                      createdRecords: createdRecords)
    }
}
