import SwiftData

public enum ExperimentSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [Experiment.self, ExperimentRecord.self, Pause.self, ExperimentStatusEntry.self]
    }
}

public enum ExperimentMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] {
        [ExperimentSchemaV1.self]
    }

    public static var stages: [MigrationStage] { [] }
}
