// Copyright © 2015 Abhishek Banthia

import Cocoa

class TimezoneDataSource: NSObject {
    var timezones: [TimezoneData] = []
    var sliderValue: Int = 0

    init(items: [TimezoneData]) {
        sliderValue = 0
        timezones = Array(items)
    }
}

extension TimezoneDataSource {
    func setSlider(value: Int) {
        sliderValue = value
    }

    func setItems(items: [TimezoneData]) {
        timezones = items
    }
}

extension TimezoneDataSource: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in _: NSTableView) -> Int {
        var totalTimezones = timezones.count

        // If totalTimezone is 0, then we can show an option to add timezones
        if totalTimezones == 0 {
            totalTimezones += 1
        }

        return totalTimezones
    }

    func tableView(_ tableView: NSTableView, viewFor _: NSTableColumn?, row: Int) -> NSView? {
        guard !timezones.isEmpty else {
            if let addCellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "addCell"), owner: self) as? AddTableViewCell {
                return addCellView
            }

            assertionFailure("Unable to create AddTableViewCell")
            return nil
        }

        guard let cellView = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "timeZoneCell"), owner: self) as? TimezoneCellView else {
            assertionFailure("Unable to create tableviewcell")
            return NSView()
        }

        let currentModel = timezones[row]
        let operation = TimezoneDataOperations(with: currentModel)

        cellView.sunriseSetTime.stringValue = operation.formattedSunriseTime(with: sliderValue)
        cellView.sunriseImage.image = currentModel.isSunriseOrSunset ? Themer.shared().sunriseImage() : Themer.shared().sunsetImage()
        cellView.relativeDate.stringValue = operation.date(with: sliderValue, displayType: .panelDisplay)
        cellView.rowNumber = row
        cellView.customName.stringValue = currentModel.formattedTimezoneLabel()
        cellView.time.stringValue = operation.time(with: sliderValue)
        cellView.noteLabel.stringValue = currentModel.note ?? CLEmptyString
        cellView.noteLabel.toolTip = currentModel.note ?? CLEmptyString
        cellView.currentLocationIndicator.isHidden = !currentModel.isSystemTimezone
        cellView.time.setAccessibilityIdentifier("ActualTime")
        cellView.relativeDate.setAccessibilityIdentifier("RelativeDate")
        cellView.layout(with: currentModel)

        cellView.setAccessibilityIdentifier(currentModel.formattedTimezoneLabel())
        cellView.setAccessibilityLabel(currentModel.formattedTimezoneLabel())

        return cellView
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard !timezones.isEmpty else {
            return 100
        }

        if let userFontSize = DataStore.shared().retrieve(key: CLUserFontSizePreference) as? NSNumber, timezones.count > row, let relativeDisplay = DataStore.shared().retrieve(key: CLRelativeDateKey) as? NSNumber {
            let model = timezones[row]
            let shouldShowSunrise = DataStore.shared().shouldDisplay(.sunrise)

            var rowHeight: Int = userFontSize == 4 ? 60 : 65

            if relativeDisplay.intValue == 3 {
                rowHeight -= 5
            }

            if shouldShowSunrise, model.selectionType == .city {
                rowHeight += 8
            }

            if let note = model.note, !note.isEmpty {
                rowHeight += userFontSize.intValue + 25
            }

            if model.isSystemTimezone {
                rowHeight += 5
            }

            rowHeight += (userFontSize.intValue * 2)
            return CGFloat(rowHeight)
        }

        return 0
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        guard !timezones.isEmpty else {
            return []
        }

        let windowController = FloatingWindowController.shared()

        if edge == .trailing {
            let swipeToDelete = NSTableViewRowAction(style: .destructive,
                                                     title: "Delete",
                                                     handler: { _, row in

                                                         if self.timezones[row].isSystemTimezone {
                                                             self.showAlertForDeletingAHomeRow(row, tableView)
                                                             return
                                                         }

                                                         let indexSet = IndexSet(integer: row)

                                                         tableView.removeRows(at: indexSet, withAnimation: NSTableView.AnimationOptions.slideUp)

                                                         if DataStore.shared().shouldDisplay(ViewType.showAppInForeground) {
                                                             windowController.deleteTimezone(at: row)
                                                         } else {
                                                             guard let panelController = PanelController.panel() else { return }
                                                             panelController.deleteTimezone(at: row)
                                                         }

            })

            if #available(OSX 10.16, *) {
                swipeToDelete.image = Themer.shared().symbolImage(for: "trash.fill")

            } else {
                swipeToDelete.image = NSImage(named: NSImage.Name("Trash"))
            }

            return [swipeToDelete]
        }

        return []
    }

    func showAlertForDeletingAHomeRow(_ row: Int, _ tableView: NSTableView) {
        NSApplication.shared.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Confirm deleting the home row? 😅"
        alert.informativeText = "This row is automatically updated when Clocker detects a system timezone change. Are you sure you want to delete this?"
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        let response = alert.runModal()
        if response.rawValue == 1000 {
            OperationQueue.main.addOperation {
                let indexSet = IndexSet(integer: row)

                tableView.removeRows(at: indexSet, withAnimation: NSTableView.AnimationOptions.slideUp)

                if DataStore.shared().shouldDisplay(ViewType.showAppInForeground) {
                    let windowController = FloatingWindowController.shared()
                    windowController.deleteTimezone(at: row)
                } else {
                    guard let panelController = PanelController.panel() else { return }
                    panelController.deleteTimezone(at: row)
                }
            }
        }
    }
}

extension TimezoneDataSource: PanelTableViewDelegate {
    func tableView(_ table: NSTableView, didHoverOver row: NSInteger) {
        for rowIndex in 0 ..< table.numberOfRows {
            if let rowCellView = table.view(atColumn: 0, row: rowIndex, makeIfNecessary: false) as? TimezoneCellView {
                if row == -1 {
                    rowCellView.extraOptions.alphaValue = 0.5
                    continue
                }

                rowCellView.extraOptions.alphaValue = (rowIndex == row) ? 1 : 0.5
            }
        }
    }
}

extension TimezoneCellView {
    func layout(with model: TimezoneData) {
        let shouldDisplay = DataStore.shared().shouldDisplay(.sunrise) && !sunriseSetTime.stringValue.isEmpty

        sunriseSetTime.isHidden = !shouldDisplay
        sunriseImage.isHidden = !shouldDisplay

        // If it's a timezone and not a place, we can't determine the sunrise/sunset time; hide the sunrise image
        if model.selectionType == .timezone, model.latitude == nil, model.longitude == nil {
            sunriseImage.isHidden = true
        }

        setupLayout()
    }
}
