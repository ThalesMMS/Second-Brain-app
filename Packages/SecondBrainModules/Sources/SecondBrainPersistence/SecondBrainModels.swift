import Foundation
import SwiftData

@available(iOS 17.0, watchOS 10.0, *)
enum SecondBrainSchemaV1: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NoteRecord.self,
            NoteEntryRecord.self,
            AudioAttachmentRecord.self,
        ]
    }

    @Model
    final class NoteRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var bodyText: String
        var searchableText: String
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        var lastViewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \NoteEntryRecord.note)
        var entries: [NoteEntryRecord] = []

        @Relationship(deleteRule: .cascade, inverse: \AudioAttachmentRecord.note)
        var audioAttachments: [AudioAttachmentRecord] = []

        init(
            id: UUID = UUID(),
            title: String,
            bodyText: String,
            searchableText: String,
            createdAt: Date,
            updatedAt: Date,
            isPinned: Bool = false,
            lastViewedAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.bodyText = bodyText
            self.searchableText = searchableText
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
            self.lastViewedAt = lastViewedAt
        }
    }

    @Model
    final class NoteEntryRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var kindRawValue: String
        var sourceRawValue: String
        var text: String
        var note: NoteRecord?

        init(
            id: UUID = UUID(),
            createdAt: Date,
            kindRawValue: String,
            sourceRawValue: String,
            text: String,
            note: NoteRecord? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.kindRawValue = kindRawValue
            self.sourceRawValue = sourceRawValue
            self.text = text
            self.note = note
        }
    }

    @Model
    final class AudioAttachmentRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var relativePath: String
        var durationSeconds: TimeInterval
        var transcript: String?
        var sourceRawValue: String
        var note: NoteRecord?

        init(
            id: UUID = UUID(),
            createdAt: Date,
            relativePath: String,
            durationSeconds: TimeInterval,
            transcript: String?,
            sourceRawValue: String,
            note: NoteRecord? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.relativePath = relativePath
            self.durationSeconds = durationSeconds
            self.transcript = transcript
            self.sourceRawValue = sourceRawValue
            self.note = note
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
enum SecondBrainSchemaV2: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NoteRecord.self,
            NoteEntryRecord.self,
        ]
    }

    @Model
    final class NoteRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var bodyText: String
        var searchableText: String
        var createdAt: Date
        var updatedAt: Date
        var isPinned: Bool
        var lastViewedAt: Date?

        @Relationship(deleteRule: .cascade, inverse: \NoteEntryRecord.note)
        var entries: [NoteEntryRecord] = []

        init(
            id: UUID = UUID(),
            title: String,
            bodyText: String,
            searchableText: String,
            createdAt: Date,
            updatedAt: Date,
            isPinned: Bool = false,
            lastViewedAt: Date? = nil
        ) {
            self.id = id
            self.title = title
            self.bodyText = bodyText
            self.searchableText = searchableText
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.isPinned = isPinned
            self.lastViewedAt = lastViewedAt
        }
    }

    @Model
    final class NoteEntryRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var kindRawValue: String
        var sourceRawValue: String
        var text: String
        var note: NoteRecord?

        init(
            id: UUID = UUID(),
            createdAt: Date,
            kindRawValue: String,
            sourceRawValue: String,
            text: String,
            note: NoteRecord? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.kindRawValue = kindRawValue
            self.sourceRawValue = sourceRawValue
            self.text = text
            self.note = note
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
enum SecondBrainSchemaV3: VersionedSchema {
    static let versionIdentifier: Schema.Version = .init(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            NoteRecord.self,
            NoteEntryRecord.self,
        ]
    }

    @Model
    final class NoteRecord {
        @Attribute(.unique) var id: UUID
        var title: String
        var bodyText: String
        var searchableText: String
        var createdAt: Date
        var updatedAt: Date

        @Relationship(deleteRule: .cascade, inverse: \NoteEntryRecord.note)
        var entries: [NoteEntryRecord] = []

        init(
            id: UUID = UUID(),
            title: String,
            bodyText: String,
            searchableText: String,
            createdAt: Date,
            updatedAt: Date
        ) {
            self.id = id
            self.title = title
            self.bodyText = bodyText
            self.searchableText = searchableText
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class NoteEntryRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var kindRawValue: String
        var sourceRawValue: String
        var text: String
        var note: NoteRecord?

        init(
            id: UUID = UUID(),
            createdAt: Date,
            kindRawValue: String,
            sourceRawValue: String,
            text: String,
            note: NoteRecord? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.kindRawValue = kindRawValue
            self.sourceRawValue = sourceRawValue
            self.text = text
            self.note = note
        }
    }
}

@available(iOS 17.0, watchOS 10.0, *)
enum SecondBrainMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            SecondBrainSchemaV1.self,
            SecondBrainSchemaV2.self,
            SecondBrainSchemaV3.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            migrateV1ToV2,
            migrateV2ToV3,
        ]
    }

    static let migrateV1ToV2 = MigrationStage.custom(
        fromVersion: SecondBrainSchemaV1.self,
        toVersion: SecondBrainSchemaV2.self,
        willMigrate: { context in
            let attachments = try context.fetch(FetchDescriptor<SecondBrainSchemaV1.AudioAttachmentRecord>())
            for attachment in attachments {
                context.delete(attachment)
            }
            try context.save()
        },
        didMigrate: nil
    )

    static let migrateV2ToV3 = MigrationStage.lightweight(
        fromVersion: SecondBrainSchemaV2.self,
        toVersion: SecondBrainSchemaV3.self
    )
}

typealias NoteRecord = SecondBrainSchemaV3.NoteRecord
typealias NoteEntryRecord = SecondBrainSchemaV3.NoteEntryRecord
