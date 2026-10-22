//
//  Clipboard.swift
//  OreMonoCAD
//
//  Edit › Cut / Copy / Paste of drawing objects – also between open drawings (tabs).
//
//  • Copy remembers copies of the selected objects together with their layers and the blocks they use.
//  • Paste (⌘V) hangs the objects on the cursor by the lower-left corner of their bounds – a click places them.
//  • Paste at Original Coordinates (⇧⌘V) puts them at the same coordinates – e.g. from the surveyor's map into a study.
//  • Layers and blocks missing in the target drawing are added to it when the objects are placed. A block
//    with the same name that already exists there is used as it is.
//

import Cocoa

/// The app's own clipboard for drawing objects (not the system one – the objects only make sense inside OreMonoCAD).
final class DrawingClipboard {
    static let shared = DrawingClipboard()

    /// Copies of the copied objects (in the coordinates of the source drawing).
    private var entities: [CADEntity] = []
    /// Layers of the source drawing used by the objects (also inside their blocks).
    private var layers: [String: Layer] = [:]

    var isEmpty: Bool { return entities.isEmpty }
    var count: Int { return entities.count }

    /// What a paste brings into the target drawing.
    struct PasteContent {
        /// Fresh copies (new identities), not yet in the drawing.
        let entities: [CADEntity]
        /// Blocks the target drawing doesn't have yet – added when the objects are placed.
        let newBlocks: [BlockDefinition]
        /// Layers the target drawing doesn't have yet.
        let newLayers: [Layer]
        /// Objects that can't go here (viewports outside a layout, a block inside itself).
        let skipped: Int
    }

    /// Remembers copies of the selected objects (the objects in the drawing are not touched).
    func store(_ selected: [CADEntity], layerManager: LayerManager) {
        entities = DrawingClipboard.copies(of: selected)
        var names = Set<String>()
        var visited = Set<ObjectIdentifier>()
        for entity in selected { DrawingClipboard.collectLayers(of: entity, into: &names, visited: &visited) }
        layers = [:]
        for name in names {
            if let layer = layerManager.getLayer(name) { layers[name] = layer }
        }
    }

    /// Fresh copies for pasting into a drawing with the given layers and blocks.
    /// `editedBlock` = the block being edited right now (a block can't contain itself),
    /// `onLayout` = pasting onto a layout (viewports only make sense there).
    func prepare(for layerManager: LayerManager, blocks library: BlockLibrary,
                 editedBlock: BlockDefinition?, onLayout: Bool) -> PasteContent {
        var result: [CADEntity] = []
        var newBlocks: [BlockDefinition] = []
        var memo: [ObjectIdentifier: BlockDefinition] = [:]
        var skipped = 0
        for entity in DrawingClipboard.copies(of: entities) {
            if entity is ViewportEntity && !onLayout {
                skipped += 1
                continue
            }
            if let reference = entity as? BlockReference {
                reference.definition = DrawingClipboard.adopt(reference.definition, into: library, created: &newBlocks, memo: &memo)
                if let edited = editedBlock, reference.definition.contains(edited) {
                    skipped += 1
                    continue
                }
            }
            result.append(entity)
        }
        // layers used by the pasted objects and by the blocks that come with them
        var names = Set<String>()
        var visited = Set<ObjectIdentifier>()
        for entity in result { DrawingClipboard.collectLayers(of: entity, into: &names, visited: &visited) }
        let newLayers = names.sorted().compactMap { name -> Layer? in
            guard layerManager.getLayer(name) == nil else { return nil }
            return layers[name] ?? Layer(name: name, color: .white)
        }
        return PasteContent(entities: result, newBlocks: newBlocks, newLayers: newLayers, skipped: skipped)
    }

    /// Clones of the objects; dimension links point to the clones (links to objects that were not copied are dropped).
    static func copies(of originals: [CADEntity]) -> [CADEntity] {
        var newID: [UUID: UUID] = [:]
        let clones = originals.map { original -> CADEntity in
            let copy = original.clone()
            newID[original.id] = copy.id
            return copy
        }
        for case let dimension as DimensionEntity in clones where !dimension.links.isEmpty {
            var links: [Int: DimensionLink] = [:]
            for (index, link) in dimension.links {
                if let target = newID[link.entityID] { links[index] = DimensionLink(entityID: target, grip: link.grip) }
            }
            dimension.links = links
        }
        return clones
    }

    /// The layer of the object and, for a block, the layers of everything inside it.
    private static func collectLayers(of entity: CADEntity, into names: inout Set<String>, visited: inout Set<ObjectIdentifier>) {
        names.insert(entity.layer)
        guard let reference = entity as? BlockReference,
              visited.insert(ObjectIdentifier(reference.definition)).inserted else { return }
        for inner in reference.definition.entities { collectLayers(of: inner, into: &names, visited: &visited) }
    }

    /// The block definition to use in the target drawing: its own (the same drawing, or a block of the same name),
    /// otherwise a copy – including the blocks nested in it – that is added to `created`.
    private static func adopt(_ definition: BlockDefinition, into library: BlockLibrary,
                              created: inout [BlockDefinition], memo: inout [ObjectIdentifier: BlockDefinition]) -> BlockDefinition {
        let key = ObjectIdentifier(definition)
        if let done = memo[key] { return done }
        if library.definitions.contains(where: { $0 === definition }) {
            memo[key] = definition
            return definition
        }
        if let existing = library.named(definition.name) {
            memo[key] = existing
            return existing
        }
        let source = definition.source.map { original -> XrefSource in
            let copy = XrefSource(path: original.path, bookmark: original.bookmark)
            copy.modified = original.modified
            copy.error = original.error
            return copy
        }
        let copy = BlockDefinition(name: definition.name, basePoint: definition.basePoint, entities: [],
                                   note: definition.note, source: source)
        memo[key] = copy
        created.append(copy)
        if copy.isExternal {
            // the content of an external reference comes from its file – only for display until it reloads
            copy.entities = definition.entities.map { $0.clone() }
            return copy
        }
        var content: [CADEntity] = []
        for entity in copies(of: definition.entities) {
            if let reference = entity as? BlockReference {
                reference.definition = adopt(reference.definition, into: library, created: &created, memo: &memo)
            }
            content.append(entity)
        }
        copy.entities = content
        return copy
    }

    /// The point the objects hang on the cursor by: the lower-left corner of their bounds.
    static func basePoint(of entities: [CADEntity]) -> CGPoint {
        var box = CGRect.null
        for entity in entities {
            let bounds = entity.boundingBox()
            guard DrawingSafety.isValidWorld(bounds) else { continue }
            box = box.union(bounds)
        }
        if !box.isNull { return CGPoint(x: box.minX, y: box.minY) }
        // only construction lines (no bounds): the point the first one goes through
        return (entities.first as? ConstructionLine)?.point ?? .zero
    }
}
