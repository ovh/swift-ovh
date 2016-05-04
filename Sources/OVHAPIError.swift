//
//  OVHAPIError.swift
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

import Foundation

/**
 All the errors from the package OVHAPIWrapper are in this enum.
 */
public enum OVHAPIError : ErrorType, CustomStringConvertible {
    case HttpError(code: Int)
    case RequestError(code: Int, httpCode: String?, errorCode: String?, message: String?)
    case InvalidRequestResponse
    case MissingApplicationKey
    case MissingApplicationSecret
    case MissingConsumerKey
    
    public var description: String {
        switch self {
        case .HttpError(let code): return "HTTP error \(code)"
        case .RequestError(_, _, _, let message):
            if let message = message {
                return message
            } else {
                return ""
            }
        case .InvalidRequestResponse: return "Invalid response"
        case .MissingApplicationKey: return "Application key is missing"
        case .MissingApplicationSecret: return "Application secret is missing"
        case .MissingConsumerKey: return "Consumer key is missing"
        }
    }
}