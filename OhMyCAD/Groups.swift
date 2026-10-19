//
//  Groups.swift
//  OhMyCAD
//
//  Groups of objects (like GROUP in AutoCAD): several objects that are selected together with one click,
//  without making a block. Each object carries the id of its group (CADEntity.groupID, saved in the drawing);
//  Edit › Group and Edit › Ungroup set and clear it. A group can't contain another group – grouping again
//  moves the objects into the new group.
//

import Cocoa

enum Groups {
    /// Keeps the groups right after a change (MainViewController.applyChange), before it is applied:
    /// - new pieces (Trim, Break, Fillet, Explode…) stay in the group when all the original objects were in one group,
    /// - copies (Copy, Mirror, Array, Paste…) of grouped objects get a group of their own,
    /// - an added object that would be alone in its group is not grouped.
    /// - Parameter inheritsGroup: false for Ungroup – the objects are meant to leave their group.
    static func adjust(added: [CADEntity], removed: [CADEntity], documentEntities: [CADEntity], inheritsGroup: Bool) {
        guard !added.isEmpty else { return }
        let removedGroups = Set(removed.compactMap { $0.groupID })

        // 1) pieces of grouped objects
        if inheritsGroup, removedGroups.count == 1, let group = removedGroups.first,
           removed.allSatisfy({ $0.groupID == group }) {
            for entity in added where entity.groupID == nil { entity.groupID = group }
        }

        let addedGroups = Set(added.compactMap { $0.groupID })
        guard !addedGroups.isEmpty else { return }
        let removedIDs = Set(removed.map { $0.id })
        let addedIDs = Set(added.map { $0.id })
        // members of those groups that stay in the drawing
        var remaining: [UUID: Int] = [:]
        for entity in documentEntities where !removedIDs.contains(entity.id) && !addedIDs.contains(entity.id) {
            if let group = entity.groupID, addedGroups.contains(group) { remaining[group, default: 0] += 1 }
        }

        // 2) copies: the group still exists in the drawing and none of its objects was edited
        var renamed: [UUID: UUID] = [:]
        for entity in added {
            guard let group = entity.groupID, remaining[group] != nil, !removedGroups.contains(group) else { continue }
            let fresh = renamed[group] ?? UUID()
            renamed[group] = fresh
            entity.groupID = fresh
        }

        // 3) a group of one object is no group
        var members: [UUID: Int] = [:]
        for entity in added {
            if let group = entity.groupID { members[group, default: 0] += 1 }
        }
        for entity in added {
            guard let group = entity.groupID else { continue }
            if (members[group] ?? 0) + (remaining[group] ?? 0) < 2 { entity.groupID = nil }
        }
    }

    /// The objects together with the other members of their groups (from `candidates`).
    static func expanded(_ entities: [CADEntity], from candidates: [CADEntity]) -> [CADEntity] {
        let groups = Set(entities.compactMap { $0.groupID })
        guard !groups.isEmpty else { return entities }
        let ids = Set(entities.map { $0.id })
        let others = candidates.filter { entity in
            guard let group = entity.groupID else { return false }
            return groups.contains(group) && !ids.contains(entity.id)
        }
        return entities + others
    }
}

extension AppSettings {
    /// A click on a grouped object selects its whole group (Edit › Select Groups as a Whole).
    static var selectWholeGroups: Bool {
        get { return UserDefaults.standard.object(forKey: "OhMyCAD.selectWholeGroups") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "OhMyCAD.selectWholeGroups") }
    }
}
