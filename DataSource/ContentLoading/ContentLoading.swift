//
//  ContentLoading.swift
//  DataSource
//
//  Created by Dmytro Anokhin on 30/08/15.
//  Copyright © 2015 Dmytro Anokhin. All rights reserved.
//


public enum ContentLoadingState {

    /// The initial state
    case initial
    
    /// Loading content
    case loading

    /// Content is loaded successfully
    case loaded
    
    /// An error occurred while loading content
    case error
    
    public var isLoaded: Bool {
        return self == .loaded || self == .error
    }
    
    public var isLoading: Bool {
        return self == .loading
    }
}


/// A protocol that defines content loading behavior
public protocol ContentLoading : ContentLoadingObservable {

    /// Current loading state.
    var loadingState: ContentLoadingState { get }
    
    /// Loading error. Valid only when loadingState == .error
    var loadingError: Error? { get }
    
    /// Used to begin loading the content.
    func loadContent()
}


public extension ContentLoading where Self: Composition {
    
    var loadingState: ContentLoadingState {
    
        // The numberOf represents number of data sources per each loading state.
        // Initial state has a value of 1 and used to return from the loop.
        var numberOf: [ContentLoadingState : UInt] = [
                .initial : 1,
                .loading : 0,
                .loaded : 0,
                .error : 0
            ]

        // Calculating number of content loading data sources per loading state.
        for child in children {
            guard let loadingState = (child as? ContentLoading)?.loadingState else { continue }
            numberOf[loadingState]! += 1
        }
        
        // Aggregate loading states by selecting one with highest priority in which there are at least one data source.
        
        let loadingStateByPriority: [ContentLoadingState] = [
            .loading, .error, .loaded, .initial
        ]
        
        for loadingState in loadingStateByPriority {
            if numberOf[loadingState]! > 0 {
                return loadingState
            }
        }
        
        // If execution reached this point this means that new loading state was added to the enum but not handled in this method.
        fatalError("All loading states must be present in the list")
    }
    
    func loadContent() {
        
        assertMainThread()
    
        for child in children {
            (child as? ContentLoading)?.loadContent()
        }
        
        if loadingState == .loading {
            contentLoadingObserver?.willLoadContent(self)
        }
    }
}
