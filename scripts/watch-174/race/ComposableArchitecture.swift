import LabcordWatchOS

@MainActor public struct DependencyValues {
  public var watchConnectivitySession: WatchConnectivitySession { WatchConnectivitySession() }
  public init() {}
}
@propertyWrapper @MainActor public struct Dependency<Value> {
  private let path: KeyPath<DependencyValues, Value>
  public init(_ path: KeyPath<DependencyValues, Value>) { self.path = path }
  public var wrappedValue: Value { DependencyValues()[keyPath: path] }
}
