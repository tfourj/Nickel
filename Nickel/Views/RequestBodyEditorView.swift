//
//  RequestBodyEditorView.swift
//  Nickel
//
//  Created by TfourJ on 5. 2. 25.
//

import SwiftUI

struct RequestBodyEditorView: View {
    @Binding var requestBodyItems: [RequestBodyItem]
    @Binding var showRequestEditor: Bool
    @Binding var showAlert: Bool
    @Binding var alertMessage: String
    
    let valueTypes = ["String", "Bool"]
    
    var body: some View {
        NavigationView {
            Form {
                ForEach(requestBodyItems.sorted { $0.order < $1.order }) { item in
                    if requestBodyItems.firstIndex(where: { $0.id == item.id }) != nil {
                        GeometryReader { geometry in
                            HStack(spacing: 0) {
                                TextField("Key", text: Binding(
                                    get: { requestBodyItems.first(where: { $0.id == item.id })?.key ?? "" },
                                    set: { newValue in
                                        if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                            requestBodyItems[idx].key = newValue
                                        }
                                    }
                                ))
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(width: geometry.size.width * 0.35, alignment: .leading)
                                
                                Menu {
                                    ForEach(valueTypes, id: \.self) { type in
                                        Button(type) {
                                            if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                requestBodyItems[idx].type = type
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(requestBodyItems.first(where: { $0.id == item.id })?.type ?? "String")
                                            .foregroundColor(.primary)
                                        Image(systemName: "chevron.down")
                                            .foregroundColor(.gray)
                                            .font(.caption)
                                    }
                                    .padding(5)
                                    .frame(width: 80)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5)
                                            .stroke(Color.gray, lineWidth: 0.5)
                                    )
                                }
                                .frame(minWidth: 80, maxWidth: 80)
                                .padding(.horizontal, 5)
                                
                                ZStack {
                                    if let currentItem = requestBodyItems.first(where: { $0.id == item.id }),
                                       currentItem.type == "Bool" {
                                        Toggle("", isOn: Binding(
                                            get: { 
                                                guard let currentItem = requestBodyItems.first(where: { $0.id == item.id }) else { return false }
                                                let value = currentItem.value.lowercased()
                                                return value == "true" || value == "1" 
                                            },
                                            set: { newValue in
                                                if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                    let currentValue = requestBodyItems[idx].value.lowercased()
                                                    let isCurrentlyTrue = currentValue == "true" || currentValue == "1"
                                                    
                                                    if newValue != isCurrentlyTrue {
                                                        if currentValue == "1" || currentValue == "0" {
                                                            requestBodyItems[idx].value = newValue ? "1" : "0"
                                                        } else {
                                                            requestBodyItems[idx].value = newValue ? "true" : "false"
                                                        }
                                                    }
                                                }
                                            }
                                        ))
                                        .labelsHidden()
                                    } else {
                                        TextField("Value", text: Binding(
                                            get: { requestBodyItems.first(where: { $0.id == item.id })?.value ?? "" },
                                            set: { newValue in
                                                if let idx = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                                                    requestBodyItems[idx].value = newValue
                                                }
                                            }
                                        ))
                                            .autocapitalization(.none)
                                            .disableAutocorrection(true)
                                            .multilineTextAlignment(.trailing)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                }
                                .frame(width: geometry.size.width * 0.35, alignment: .trailing)
                            }
                        }
                        .frame(height: 40)
                    }
                }
                .onDelete { indices in
                    let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
                    let itemsToDelete = indices.map { sortedItems[$0] }
                    
                    for itemToDelete in itemsToDelete {
                        if let index = requestBodyItems.firstIndex(where: { $0.id == itemToDelete.id }) {
                            requestBodyItems.remove(at: index)
                        }
                    }
                    
                    for (newOrder, item) in requestBodyItems.sorted(by: { $0.order < $1.order }).enumerated() {
                        if let index = requestBodyItems.firstIndex(where: { $0.id == item.id }) {
                            requestBodyItems[index].order = newOrder
                        }
                    }
                }
                .onMove { source, destination in
                    let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
                    var newOrderedItems = sortedItems
                    newOrderedItems.move(fromOffsets: source, toOffset: destination)
                    
                    for (newOrder, movedItem) in newOrderedItems.enumerated() {
                        if let index = requestBodyItems.firstIndex(where: { $0.id == movedItem.id }) {
                            requestBodyItems[index].order = newOrder
                        }
                    }
                }
                
                Button("Add New Item") {
                    let newOrder = (requestBodyItems.map { $0.order }.max() ?? -1) + 1
                    requestBodyItems.append(RequestBodyItem(key: "", value: "", type: "String", order: newOrder))
                }
            }
            .navigationTitle("Request Body Editor")
            .navigationBarItems(
                leading: Button("Cancel") {
                    showRequestEditor = false
                },
                trailing: EditButton()
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveRequestBody()
                        showRequestEditor = false
                    }
                }
            }
        }
    }
    
    private func saveRequestBody() {
        var jsonObject: [String: Any] = [:]
        var orderArray: [String] = []
        
        let sortedItems = requestBodyItems.sorted { $0.order < $1.order }
        
        for item in sortedItems {
            orderArray.append(item.key)
            if item.type == "Bool" {
                if item.value == "1" {
                    jsonObject[item.key] = true
                } else if item.value == "0" {
                    jsonObject[item.key] = false
                } else {
                    jsonObject[item.key] = item.value.lowercased() == "true"
                }
            } else {
                jsonObject[item.key] = item.value
            }
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            UserDefaults.standard.set(jsonString, forKey: "customRequestBody")
            
            if let orderData = try? JSONSerialization.data(withJSONObject: orderArray, options: []) {
                UserDefaults.standard.set(orderData, forKey: "requestBodyOrder")
            }
            
            alertMessage = "Settings saved successfully"
        } else {
            alertMessage = "Failed to save request body"
        }
        showAlert = true
    }
}

#Preview {
    RequestBodyEditorView(
        requestBodyItems: .constant([]),
        showRequestEditor: .constant(false),
        showAlert: .constant(false),
        alertMessage: .constant("")
    )
} 
