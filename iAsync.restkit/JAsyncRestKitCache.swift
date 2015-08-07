//
//  JAsyncRestKitCache.swift
//  JRestKit
//
//  Created by Vladimir Gorbenko on 22.09.14.
//  Copyright (c) 2014 EmbeddedSources. All rights reserved.
//

import Foundation

import iAsync_async

public protocol JAsyncRestKitCache {
    
    func loaderToSetData(data: NSData, forKey key: String) -> JAsyncTypes<NSNull, NSError>.JAsync
    
    func cachedDataLoaderForKey(key: String) -> JAsyncTypes<JRestKitCachedData, NSError>.JAsync
}
