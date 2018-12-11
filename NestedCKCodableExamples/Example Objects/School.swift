//
//  School.swift
//  CloudKitCodable
//
//  Created by Guilherme Girotto on 18/11/18.
//  Copyright © 2018 Guilherme Girotto. All rights reserved.
//

import CoreLocation
import UIKit
import NestedCloudKitCodable

struct School: CKCodable {
    var cloudKitRecordType: String {
        return "School"
    }
    
    var id: String
    var name: String
    var location: CLLocation
    var students: [Person]
    var director: Person
    var books: [Book]
    
    private enum CodingKeys: String, CodingKey {
        case id, name, location, students, director, books
    }
    
    init(id: String = UUID().uuidString, name: String, location: CLLocation, students: [Person], director: Person, books: [Book]) {
        self.id = id
        self.name = name
        self.location = location
        self.students = students
        self.director = director
        self.books = books
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.name = try container.decode(String.self, forKey: .name)
        self.id = try container.decode(String.self, forKey: .id)
        
        let stringLocation = try container.decode(String.self, forKey: .location)
        let splitedLocation = stringLocation.split(separator: ";")
        let schoolLocation = CLLocation(latitude: Double(splitedLocation[0])!, longitude: Double(splitedLocation[1])!)
        self.location = schoolLocation
        
        self.students = try container.decode([Person].self, forKey: .students)
        self.director = try container.decode(Person.self, forKey: .director)
        self.books = try container.decode([Book].self, forKey: .books)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(name, forKey: .name)
        
        let formattedLocation = "\(location.coordinate.latitude);\(location.coordinate.longitude)"
        try container.encode(formattedLocation, forKey: .location)
        
        try container.encode(students, forKey: .students)
        try container.encode(director, forKey: .director)
        try container.encode(books, forKey: .books)
    }
}
