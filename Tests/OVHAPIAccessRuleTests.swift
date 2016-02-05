//
//  OVHAPIAccessRuleTests.swift
//
//  Copyright (c) 2016, OVH SAS.
//  All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  * Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  * Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//  * Neither the name of OVH SAS nor the
//  names of its contributors may be used to endorse or promote products
//  derived from this software without specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY OVH SAS AND CONTRIBUTORS ``AS IS'' AND ANY
//  EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL OVH SAS AND CONTRIBUTORS BE LIABLE FOR ANY
//  DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
//  (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
//  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
//  ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
//  (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
//  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

import XCTest
@testable import OVHAPIWrapper

class OVHAPIAccessRuleTests: XCTestCase {
    
    // MARK: - Lifecycle
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    
    // MARK: - Tests
    
    func testDistionaryRepresentations() {
        XCTAssertEqual(OVHAPIAccessRule(method: .GET, path: "/*").dictionaryRepresentation(), ["method": "GET", "path": "/*"], "The dictionary representation of a GET access rule must return the right dictionary object.")
        XCTAssertEqual(OVHAPIAccessRule(method: .POST, path: "/*").dictionaryRepresentation(), ["method": "POST", "path": "/*"], "The dictionary representation of a POST access rule must return the right dictionary object.")
        XCTAssertEqual(OVHAPIAccessRule(method: .PUT, path: "/*").dictionaryRepresentation(), ["method": "PUT", "path": "/*"], "The dictionary representation of a PUT access rule must return the right dictionary object.")
        XCTAssertEqual(OVHAPIAccessRule(method: .DELETE, path: "/*").dictionaryRepresentation(), ["method": "DELETE", "path": "/*"], "The dictionary representation of a DELETE access rule must return the right dictionary object.")
    }

    func testShorthandAllRights() {
        let allRights = OVHAPIAccessRule.allRights()
        let rights = [OVHAPIAccessRule(method: .GET, path: "/*"), OVHAPIAccessRule(method: .POST, path: "/*"), OVHAPIAccessRule(method: .PUT, path: "/*"), OVHAPIAccessRule(method: .DELETE, path: "/*")]
        
        XCTAssertTrue(rulesAreEqual(allRights, otherRights: rights), "The 'allRights()' shorthand must return the right access rules.")
    }
    
    func testShorthandAllRightsWithPath() {
        let allRights = OVHAPIAccessRule.allRights("/vps/*")
        let rights = [OVHAPIAccessRule(method: .GET, path: "/vps/*"), OVHAPIAccessRule(method: .POST, path: "/vps/*"), OVHAPIAccessRule(method: .PUT, path: "/vps/*"), OVHAPIAccessRule(method: .DELETE, path: "/vps/*")]
        
        XCTAssertTrue(rulesAreEqual(allRights, otherRights: rights), "The 'allRights(path:)' shorthand must return the right access rules.")
    }
    
    func testShorthandReadOnlyRights() {
        let allRights = OVHAPIAccessRule.readOnlyRights()
        let rights = [OVHAPIAccessRule(method: .GET, path: "/*")]
        
        XCTAssertTrue(rulesAreEqual(allRights, otherRights: rights), "The 'readOnlyRights()' shorthand must return the right access rules.")
    }
    
    func testShorthandReadOnlyRightsWithPath() {
        let allRights = OVHAPIAccessRule.readOnlyRights("/vps/*")
        let rights = [OVHAPIAccessRule(method: .GET, path: "/vps/*")]
        
        XCTAssertTrue(rulesAreEqual(allRights, otherRights: rights), "The 'readOnlyRights(path:)' shorthand must return the right access rules.")
    }
    
    
    // MARK: - Methods
    
    private func rulesAreEqual(rights: [OVHAPIAccessRule], otherRights: [OVHAPIAccessRule]) -> Bool {
        return rights.elementsEqual(otherRights) { $0.method.rawValue == $1.method.rawValue && $0.path == $1.path }
    }

}
