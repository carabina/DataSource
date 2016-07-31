//
//  TableViewComposedDataSource.swift
//
//  Created by Dmytro Anokhin on 25/06/15.
//  Copyright © 2015 danokhin. All rights reserved.
//


public class TableViewComposedDataSource: NSObject, ComposedDataSourceType, TableViewDataSourceType,
    TableViewReusableViewsRegistering, ContentLoading, UpdateObserver, UpdateObservable, ContentLoadingObserver, ContentLoadingObservable {

    public typealias ChildDataSource = TableViewDataSourceType

    // MARK: - TableViewDataSourceType

    private var _numberOfSections: Int = 0
    
    public var numberOfSections: Int {
        updateMappings()
        return _numberOfSections
    }
    
    // MARK: - DataSourceType
    
    public func object(at indexPath: IndexPath) -> Any? {
        
        guard let mapping = self.mapping(for: indexPath.section),
              let localIndexPath = mapping.localIndexPath(for: indexPath)
        else {
            return nil
        }
        
        return mapping.dataSource.object(at: localIndexPath)
    }
    
    public func indexPaths(for object: Any) -> [IndexPath] {
        
        return dataSources.reduce([]) { indexPaths, dataSource in
            let mapping = self.mapping(for: dataSource)
            let localIndexPaths = dataSource.indexPaths(for: object)
            
            return indexPaths + localIndexPaths.flatMap { mapping.globalIndexPath(for: $0) }
        }
    }
    
    // MARK: - ComposedDataSourceType

    @discardableResult
    public func add(dataSource: ChildDataSource, animated: Bool) -> Bool {
    
        assertMainThread()

        if nil != dataSourceToMappings.object(forKey: dataSource) {
            assertionFailure("Tried to add data source more than once: \(dataSource)")
            return false
        }

        (dataSource as? UpdateObservable)?.updateObserver = self
        (dataSource as? ContentLoadingObservable)?.contentLoadingObserver = self

        let mapping = ComposedTableViewMapping(dataSource: dataSource)
        mappings.append(mapping)
        dataSourceToMappings.setObject(mapping, forKey: dataSource)
        
        updateMappings()
        
        let sections = self.sections(for: dataSource)
        notify(update: TableViewUpdate.insertSections(sections, animation: animated ? .automatic : .none))
        
        return true
    }
    
    @discardableResult
    public func remove(dataSource: ChildDataSource, animated: Bool)  -> Bool {
    
        assertMainThread()
        
        guard let mapping = dataSourceToMappings.object(forKey: dataSource) else {
            assertionFailure("Data source not found in mapping: \(dataSource)")
            return false
        }
        
        let sections = self.sections(for: dataSource)
        
        dataSourceToMappings.removeObject(forKey: dataSource)
        if let index = mappings.index(where: { $0 === mapping }) {
            mappings.remove(at: index)
        }

        (dataSource as? UpdateObservable)?.updateObserver = nil
        (dataSource as? ContentLoadingObservable)?.contentLoadingObserver = nil
        
        updateMappings()
        notify(update: TableViewUpdate.deleteSections(sections, animation: animated ? .automatic : .none))
        
        return true
    }
    
    public var dataSources: [ChildDataSource] {
        return mappings.map { $0.dataSource }
    }
    
    // MARK: - ContentLoading
    
    private var aggregatedLoadingState: ContentLoadingState?

    public var loadingState: ContentLoadingState {
        if let aggregatedLoadingState = aggregatedLoadingState {
            return aggregatedLoadingState
        }
        
        return updateAggregatedLoadingState()
    }
    
    public var loadingError: NSError?

    public func loadContent() {
        for dataSource in dataSources {
            (dataSource as? ContentLoading)?.loadContent()
        }
    }
    
    public var pendingUpdate: Update?

    @discardableResult
    private func updateAggregatedLoadingState() -> ContentLoadingState {
    
        // The numberOf represents number of data sources per each loading state.
        // Initial state has a value of 1 and used to return from the loop.
        var numberOf: [ContentLoadingState : UInt] = [
                .initial : 1,
                .loadingContent : 0,
                .contentLoaded : 0,
                .noContent : 0,
                .error : 0
            ]

        // Calculating number of content loading data sources per loading state.
        for dataSource in dataSources {
            guard let loadingState = (dataSource as? ContentLoading)?.loadingState else { continue }
            numberOf[loadingState]! += 1
        }
        
        // Aggregate loading states by selecting one with highest priority in which there are at least one data source.
        
        let loadingStateByPriority: [ContentLoadingState] = [
            .loadingContent, .error, .noContent, .contentLoaded, .initial
        ]
        
        for loadingState in loadingStateByPriority {
            if numberOf[loadingState]! > 0 {
                aggregatedLoadingState = loadingState
                return loadingState
            }
        }
        
        // If execution reached this point this means that new loading state was added to the enum but not handled in this method.
        fatalError("All loading states must be present in the list")
    }

    
    // MARK: - UpdateObservable
    
    public weak var updateObserver: UpdateObserver?
    
    public func notify(update: Update) {

        assertMainThread()
        updateObserver?.perform(update: update, from: self)
    }
    
    // MARK: - UpdateObserver
    
    public func perform(update: Update, from sender: UpdateObservable) {
        
        guard let dataSource = sender as? TableViewDataSourceType else { return }
        
        if let _ = update as? TableViewBatchUpdate {
            updateMappings()
            notify(update: update)
            return
        }
        
        if let _ = update as? TableViewReloadDataUpdate {
            updateMappings()
            notify(update: update)
            return
        }
    
        guard let structureUpdate = update as? TableViewStructureUpdate else {
            notify(update: update)
            return
        }
    
        let mapping = self.mapping(for: dataSource)
        
        notify(update: structureUpdate.dynamicType.init(type: structureUpdate.type, animation: structureUpdate.animation,
            indexPaths: {
                guard let indexPaths = structureUpdate.indexPaths else { return nil }
                // Map local index paths to global
                return mapping.globalIndexPaths(for: indexPaths)
            }(),
            newIndexPaths: {
                guard let newIndexPaths = structureUpdate.newIndexPaths else { return nil }
                // Map local index path to global
                return mapping.globalIndexPaths(for: newIndexPaths)
            }(),
            sections: {
                guard let sections = structureUpdate.sections else { return nil }
                
                switch structureUpdate.type {
                    case .insert:
                        updateMappings()
                        // Map local sections to global after mappings update
                        return globalSections(for: sections, in: dataSource)
                    case .delete:
                        // Map local sections to global before mappings update
                        let globalSections = self.globalSections(for: sections, in: dataSource)
                        updateMappings()
                        return globalSections
                    case .reload:
                        // Map local sections to global without mappings update
                        return globalSections(for: sections, in: dataSource)
                    case .move:
                        // Map local sections to global without mappings update, mappings update must happen in newSections
                        return globalSections(for: sections, in: dataSource)
                }
            }(),
            newSections: {
                guard let newSections = structureUpdate.newSections else { return nil }
                updateMappings()
                let globalNewSection = mapping.globalSections(for: newSections)
                
                return globalNewSection
            }()
        ))
    }
    
    // MARK: - ContentLoadingObservable
    
    public weak var contentLoadingObserver: ContentLoadingObserver?
    
    // MARK: - ContentLoadingObserver
    
    public func willLoadContent(_ sender: ContentLoadingObservable) {
        
        assertMainThread()

        let previousLoadingState = aggregatedLoadingState
        updateAggregatedLoadingState()
        
        if loadingState == .loadingContent && previousLoadingState != loadingState { // Notify only once - first time loading starts
            contentLoadingObserver?.willLoadContent(self)
        }
    }
    
    public func didLoadContent(_ sender: ContentLoadingObservable, with error: NSError?) {
        
        assertMainThread()
        
        let previousLoadingState = loadingState
        updateAggregatedLoadingState()
        
        if previousLoadingState == loadingState {
            return
        }
        
        // Enqueue update or perform if loading completed
        
        let batchUpdate = BatchUpdate()
        
        if let pendingUpdate = pendingUpdate {
            batchUpdate.enqueueUpdate(pendingUpdate)
            self.pendingUpdate = nil // Prevent looping on executing pending updates
        }

        batchUpdate.enqueueUpdate(.arbitraryUpdate({
            guard let pendingUpdate = self.pendingUpdate else { return }
            self.notify(update: pendingUpdate)
        }))

        switch loadingState {
            case .loadingContent:
                pendingUpdate = batchUpdate

            default:
                notify(update: batchUpdate)
                contentLoadingObserver?.didLoadContent(self, with: error)
        }
    }

    // MARK: - UITableViewDataSource
    
    // required
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    
        updateMappings()
    
        guard let mapping = self.mapping(for: section) else {
            fatalError("Mapping for section not found: \(section)")
        }
        
        guard let localSection = mapping.localSection(for: section) else {
            fatalError("Local section for section not found: \(section)")
        }
        
        let wrapper = ComposedTableViewWrapper.wrapper(for: tableView, mapping: mapping)
        let dataSource = mapping.dataSource
        
        return dataSource.tableView(wrapper, numberOfRowsInSection: localSection)
    }
    
    public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    
        guard let mapping = self.mapping(for: indexPath.section) else {
            fatalError("Mapping for index path not found: \(indexPath)")
        }
        
        guard let localIndexPath = mapping.localIndexPath(for: indexPath) else {
            fatalError("Local index path for index path not found: \(indexPath)")
        }
        
        let wrapper = ComposedTableViewWrapper.wrapper(for: tableView, mapping: mapping)
        
        return mapping.dataSource.tableView(wrapper, cellForRowAt: localIndexPath)
    }
    
    // optional
    
    public func numberOfSections(in tableView: UITableView) -> Int {
        return numberOfSections
    }
    
    // MARK: - Private
    
    private var mappings: [ComposedTableViewMapping] = []
    
    // TODO: Figure out how to specify ChildDataSource in generic
    private var dataSourceToMappings = MapTable<AnyObject, ComposedTableViewMapping>(
        keyOptions: .objectPointerPersonality, valueOptions: PointerFunctions.Options(), capacity: 1)

    private var globalSectionToMappings: [Int: ComposedTableViewMapping] = [:]
    
    private func updateMappings() {
        _numberOfSections = 0
        globalSectionToMappings.removeAll()
        
        for mapping in mappings {
            let newNumberOfSections = mapping.updateMappings(startingWith: _numberOfSections)
            while _numberOfSections < newNumberOfSections {
                globalSectionToMappings[_numberOfSections] = mapping
                _numberOfSections += 1
            }
        }
    }

    private func sections(for dataSource: ChildDataSource) -> IndexSet {
    
        let mapping = self.mapping(for: dataSource)
        let sections = NSMutableIndexSet()
        
        if 0 == dataSource.numberOfSections {
            return sections as IndexSet
        }
        
        for section in 0..<dataSource.numberOfSections {
            if let globalSection = mapping.globalSection(for: section) {
                sections.add(globalSection)
            }
        }
        
        return sections as IndexSet
    }
    
    private func section(for dataSource: TableViewDataSourceType) -> Int? {
        return mapping(for: dataSource).globalSection(for: 0)
    }
    
    private func localIndexPath(for globalIndexPath: IndexPath) -> IndexPath? {
        return mapping(for: globalIndexPath.section)?.localIndexPath(for: globalIndexPath)
    }
    
    private func mapping(for section: Int) -> ComposedTableViewMapping? {
        return globalSectionToMappings[section]
    }

    private func mapping(for dataSource: TableViewDataSourceType) -> ComposedTableViewMapping {
    
        guard let mapping = dataSourceToMappings.object(forKey: dataSource) else {
            fatalError("Mapping for data source not found: \(dataSource)")
        }
        
        return mapping
    }
    
    private func globalSections(for localSections: IndexSet, in dataSource: TableViewDataSourceType) -> IndexSet {

        let mapping = self.mapping(for: dataSource)
        return mapping.globalSections(for: localSections)
    }
    
    private func globalIndexPaths(for localIndexPaths: [IndexPath], in dataSource: TableViewDataSourceType) -> [IndexPath] {
        let mapping = self.mapping(for: dataSource)
        return localIndexPaths.flatMap { mapping.globalIndexPath(for: $0) }
    }
}
