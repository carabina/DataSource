//
//  TableViewContentLoadingTests.swift
//  DataSource
//
//  Created by Dmytro Anokhin on 06/08/16.
//  Copyright © 2016 Dmytro Anokhin. All rights reserved.
//

import XCTest
@testable import DataSource


class TestContentLoadingTableViewDataSource : TestTableViewDataSource {
    
    /// Content to load. This represents sections which are loaded in loadContent call.
    let sectionToLoad: [Int]
    
    /// Error to fail content loading
    let errorToFail: NSError?
    
    required init(sections: [Int], sectionToLoad: [Int] = [], errorToFail: NSError? = nil) {
        self.sectionToLoad = sectionToLoad
        self.errorToFail = errorToFail
        super.init(sections: sections)
    }
    
    required init(sections: [Int]) {
        self.sectionToLoad = []
        self.errorToFail = nil
        super.init(sections: sections)
    }
    
    override func loadContent() {
        contentLoadingController.loadContent { coordinator in
            DispatchQueue.global().async {
                guard coordinator.current else {
                    coordinator.ignore()
                    return
                }
                
                if let error = self.errorToFail {
                    coordinator.doneWithError(error)
                    return
                }
                
                coordinator.updateWithContent { [weak self] in
                    guard let me = self else { return }
                    me.sections = me.sectionToLoad
                    me.notify(update: TableViewUpdate.reloadData())
                }
            }
        }
    }
}


class TableViewContentLoadingTests: XCTestCase {
    
    var tableView: UITableView!
    
    override func setUp() {
        super.setUp()
        
        tableView = UITableView(frame: CGRect(x: 0.0, y: 0.0, width: 320.0, height: 1000.0))
        tableView.setNeedsLayout()
        tableView.layoutIfNeeded()
    }
    
    override func tearDown() {
        tableView = nil
        super.tearDown()
    }

    // MARK: - Test successful loading

    func testContentLoadingInSingleDataSource() {
        
        // Setup empty data source with a single section containing 1 row to load
        let dataSource = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [1])
        dataSource.registerReusableViews(with: tableView)
        
        tableView.dataSource = dataSource
        tableView.reloadData()
        
        // Verify loading state and number of sections
        XCTAssertEqual(dataSource.loadingState, .initial)
        XCTAssertEqual(tableView.numberOfSections, 0)
        
        // Setup expectations and observers
        let contentLoadingObserver = ExpectationContentLoadingObserver(
            willLoadContentExpectation: expectation(description: "willLoadContentExpectation"),
            didLoadContentExpectation: expectation(description: "didLoadContentExpectation"))
        dataSource.contentLoadingObserver = contentLoadingObserver
        
        let updateObserver = ClosureUpdateObserver { $0.0.perform(self.tableView) }
        dataSource.updateObserver = updateObserver
        
        // Begin loading and verify state
        dataSource.loadContent()
        XCTAssertEqual(dataSource.loadingState, .loadingContent)

        waitForExpectations(timeout: 0.1) { error in
            // Keep observers alive
            let _ = contentLoadingObserver
            let _ = updateObserver
            
            // Verify loading state, number of sections and rows
            XCTAssertEqual(dataSource.loadingState, .contentLoaded)
            XCTAssertEqual(self.tableView.numberOfSections, 1)
            XCTAssertEqual(self.tableView.numberOfRows(inSection: 0), 1)
        }
    }

    func testContentLoadingInComposedDataSource() {
    
        // Setup data sources with content to load, data source without loading logic and composed data source.
        let dataSource1 = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [1])
        let dataSource2 = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [2])
        let dataSource3 = TestTableViewDataSource(sections: [])
        
        let dataSource = TableViewComposedDataSource()
        dataSource.add(dataSource1)
        dataSource.add(dataSource2)
        dataSource.add(dataSource3)
        
        dataSource.registerReusableViews(with: tableView)
        
        tableView.dataSource = dataSource
        tableView.reloadData()
        
        // Verify loading state and number of sections.
        XCTAssertEqual(dataSource.loadingState, .initial)
        XCTAssertEqual(tableView.numberOfSections, 0)

        // Setup expectations and observers.
        let contentLoadingObserver = ExpectationContentLoadingObserver(
            willLoadContentExpectation: expectation(description: "willLoadContentExpectation"),
            didLoadContentExpectation: expectation(description: "didLoadContentExpectation"))
        dataSource.contentLoadingObserver = contentLoadingObserver
        
        let updateObserver = ClosureUpdateObserver { $0.0.perform(self.tableView) }
        dataSource.updateObserver = updateObserver
        
        // Begin loading and verify state.
        dataSource.loadContent()
        XCTAssertEqual(dataSource.loadingState, .loadingContent)
        
        waitForExpectations(timeout: 0.1) { error in
            // Keep observers alive.
            let _ = contentLoadingObserver
            let _ = updateObserver
            
            // Verify loading state, number of sections and rows.
            XCTAssertEqual(dataSource.loadingState, .contentLoaded)
            XCTAssertEqual(self.tableView.numberOfSections, 2)
            XCTAssertEqual(self.tableView.numberOfRows(inSection: 0), 1)
            XCTAssertEqual(self.tableView.numberOfRows(inSection: 1), 2)
        }
    }
    
    // MARK: - Test loading failure
    
    static let errorDomain = "Tests"
    static let errorCode = 1
    
    func makeError() -> NSError {
        return NSError(domain: TableViewContentLoadingTests.errorDomain,
            code: TableViewContentLoadingTests.errorCode, userInfo: nil)
    }
    
    func testContentLoadingFailureInSingleDataSource() {
        
        // Setup empty data source with a single section containing 1 row to load and error to fail.
        let dataSource = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [1], errorToFail: makeError())
        dataSource.registerReusableViews(with: tableView)
        
        tableView.dataSource = dataSource
        tableView.reloadData()
        
        // Verify loading state and number of sections.
        XCTAssertEqual(dataSource.loadingState, .initial)
        XCTAssertEqual(tableView.numberOfSections, 0)
        
        // Setup expectations and observers.
        let contentLoadingObserver = ExpectationContentLoadingObserver(
            willLoadContentExpectation: expectation(description: "willLoadContentExpectation"),
            didLoadContentExpectation: expectation(description: "didLoadContentExpectation"))
        dataSource.contentLoadingObserver = contentLoadingObserver
        
        let updateObserver = ClosureUpdateObserver { $0.0.perform(self.tableView) }
        dataSource.updateObserver = updateObserver
        
        // Begin loading and verify state.
        dataSource.loadContent()
        XCTAssertEqual(dataSource.loadingState, .loadingContent)

        waitForExpectations(timeout: 0.1) { error in
            // Keep observers alive.
            let _ = contentLoadingObserver
            let _ = updateObserver
            
            // Verify loading state, number of sections must remain unchanged.
            XCTAssertEqual(dataSource.loadingState, .error)
            XCTAssertEqual(self.tableView.numberOfSections, 0)
            
            // Verify error
            let testError = self.makeError()
            XCTAssertEqual(dataSource.loadingError!, testError)
        }
    }
    
    func testContentLoadingFailureInComposedDataSource() {

        // Setup data sources with content to load, error to fail, data source without content loading logic and composed data source.
        let dataSource1 = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [1], errorToFail: makeError())
        let dataSource2 = TestContentLoadingTableViewDataSource(sections: [], sectionToLoad: [2])
        let dataSource3 = TestTableViewDataSource(sections: [])
        
        let dataSource = TableViewComposedDataSource()
        dataSource.add(dataSource1)
        dataSource.add(dataSource2)
        dataSource.add(dataSource3)
        
        dataSource.registerReusableViews(with: tableView)
        
        tableView.dataSource = dataSource
        tableView.reloadData()
        
        // Verify loading state and number of sections.
        XCTAssertEqual(dataSource.loadingState, .initial)
        XCTAssertEqual(tableView.numberOfSections, 0)

        // Setup expectations and observers.
        let contentLoadingObserver = ExpectationContentLoadingObserver(
            willLoadContentExpectation: expectation(description: "willLoadContentExpectation"),
            didLoadContentExpectation: expectation(description: "didLoadContentExpectation"))
        dataSource.contentLoadingObserver = contentLoadingObserver
        
        let updateObserver = ClosureUpdateObserver { $0.0.perform(self.tableView) }
        dataSource.updateObserver = updateObserver
        
        // Begin loading and verify state.
        dataSource.loadContent()
        XCTAssertEqual(dataSource.loadingState, .loadingContent)
        
        waitForExpectations(timeout: 0.1) { error in
            // Keep observers alive.
            let _ = contentLoadingObserver
            let _ = updateObserver
            
            // Verify loading state, number of sections and rows.
            XCTAssertEqual(dataSource.loadingState, .error)
            XCTAssertEqual(self.tableView.numberOfSections, 1)
            XCTAssertEqual(self.tableView.numberOfRows(inSection: 0), 2)
            
            // Verify error
            let testError = self.makeError()
            XCTAssertEqual(dataSource1.loadingError!, testError)
        }
    }
}

