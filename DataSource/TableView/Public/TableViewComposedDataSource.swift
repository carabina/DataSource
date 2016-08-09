//
//  TableViewComposedDataSource.swift
//
//  Created by Dmytro Anokhin on 25/06/15.
//  Copyright © 2015 danokhin. All rights reserved.
//


public class TableViewComposedDataSource : DataSource, Composable, TableViewDataSourceType,
    IndexPathIndexable, TableViewReusableViewsRegistering, ContentLoading,
    UpdateObserver, ContentLoadingObserver, ContentLoadingObservable {
    
    // MARK: - Composable

    public typealias Child = TableViewDataSourceType

    @discardableResult
    public func add(_ dataSource: Child) -> Bool {
    
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
        
        _numberOfSections = updateMappings()
        
        let sections = self.sections(for: dataSource)
        notifyUpdate(TableViewUpdate.insertSections(sections))
        
        return true
    }
    
    @discardableResult
    public func remove(_ dataSource: Child)  -> Bool {
    
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
        
        _numberOfSections = updateMappings()
        notifyUpdate(TableViewUpdate.deleteSections(sections))
        
        return true
    }
    
    public var children: [Child] {
        return mappings.map { $0.dataSource }
    }
    
    // MARK: - TableViewDataSourceType

    private var _numberOfSections: Int = 0
    
    public var numberOfSections: Int {
        _numberOfSections = updateMappings()
        return _numberOfSections
    }
    
    // MARK: - IndexPathIndexable
    
    public func object(at indexPath: IndexPath) -> Any? {
        
        guard let mapping = self.mapping(for: indexPath.section),
              let localIndexPath = mapping.localIndexPath(for: indexPath)
        else {
            return nil
        }
        
        return (mapping.dataSource as? IndexPathIndexable)?.object(at: localIndexPath)
    }
    
    public func indexPaths(for object: Any) -> [IndexPath] {
        
        return children.reduce([]) { indexPaths, dataSource in
            let mapping = self.mapping(for: dataSource)
            let localIndexPaths = (mapping.dataSource as? IndexPathIndexable)?.indexPaths(for: object) ?? []
            
            return indexPaths + localIndexPaths.flatMap { mapping.globalIndexPath(for: $0) }
        }
    }
    
    // MARK: - ContentLoading

    public var loadingError: NSError?

    // MARK: - UpdateObserver
    
    public func perform(update: Update, from sender: UpdateObservable) {
        
        guard let dataSource = sender as? TableViewDataSourceType else { return }
        
        if let _ = update as? TableViewBatchUpdate {
            _numberOfSections = updateMappings()
            notifyUpdate(update)
            return
        }
        
        if let _ = update as? TableViewReloadDataUpdate {
            _numberOfSections = updateMappings()
            notifyUpdate(update)
            return
        }
    
        guard let structureUpdate = update as? TableViewStructureUpdate else {
            notifyUpdate(update)
            return
        }
    
        let mapping = self.mapping(for: dataSource)
        
        notifyUpdate(structureUpdate.dynamicType.init(type: structureUpdate.type, animation: structureUpdate.animation,
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
                        _numberOfSections = updateMappings()
                        // Map local sections to global after mappings update
                        return globalSections(for: sections, in: dataSource)
                    case .delete:
                        // Map local sections to global before mappings update
                        let globalSections = self.globalSections(for: sections, in: dataSource)
                        _numberOfSections = updateMappings()
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
                _numberOfSections = updateMappings()
                let globalNewSection = mapping.globalSections(for: newSections)
                
                return globalNewSection
            }()
        ))
    }
    
    // MARK: - ContentLoadingObservable
    
    public weak var contentLoadingObserver: ContentLoadingObserver?
    
    // MARK: - ContentLoadingObserver
    
    public func willLoadContent(_ sender: ContentLoadingObservable) {
    }

    public func didLoadContent(_ sender: ContentLoadingObservable, with error: NSError?) {
        
        assertMainThread()

        guard loadingState.isLoaded else {
            return
        }
        
        if loadingState.isLoaded {
            performPendingUpdate()
            contentLoadingObserver?.didLoadContent(self, with: error)
        }
    }

    // MARK: - UITableViewDataSource
    
    // required
    
    public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    
        _numberOfSections = updateMappings()
    
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
    private var dataSourceToMappings = NSMapTable<AnyObject, ComposedTableViewMapping>(
        keyOptions: .objectPointerPersonality, valueOptions: NSPointerFunctions.Options(), capacity: 1)

    private var globalSectionToMappings: [Int: ComposedTableViewMapping] = [:]
    
    /// Updates map of table view sections to data sources. Returns number of global sections.
    private func updateMappings() -> Int {
        var numberOfSections = 0
        globalSectionToMappings.removeAll()
        
        for mapping in mappings {
            let newNumberOfSections = mapping.updateMappings(startingWith: numberOfSections)
            while numberOfSections < newNumberOfSections {
                globalSectionToMappings[numberOfSections] = mapping
                numberOfSections += 1
            }
        }
        
        return numberOfSections
    }

    private func sections(for dataSource: Child) -> IndexSet {
    
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
