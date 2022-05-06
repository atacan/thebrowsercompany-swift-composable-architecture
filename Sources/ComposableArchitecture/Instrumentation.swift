import Foundation

/// Interface to enable tracking/instrumenting the activity within TCA as ``Actions`` are sent into ``Store``s and
/// ``ViewStores``, ``Reducers`` are executed, and ``Effects`` are observed.
///
/// The way the library will call the closures provided is identical to the way that the ``Actions`` and ``Effects`` are
/// handled internally. That means that there is likely to be ``Instrumentation.ViewStore`` `will|did` pairs contained
/// within the bounds of an ``Instrumentation.Store`` `will|did` pair. For example: Consider sending a simple ``Action``
/// into a ``ViewStore`` that does not produce any synchronous ``Effects`` to be generated by a ``Reducer``, and the
/// ``ViewStore`` is scoped off a parent ``Store``s state:
///   1. An ``Action`` is passed to ``ViewStore.send``
///   2. The ``Instrumentation.ViewStore.willSend`` callback is called
///   3. The ``Action`` is passed to ``Store.send``
///   4. The ``Instrumentation.Store.willSend`` callback is called
///   5. The ``Instrumentation.Store.willProcessEvents`` callback is called
///   6. The ``Action`` is passed to the ``Store.reducer`` and acted upon
///   7. The ``Store.reducer`` returns an ``Effect.none`` producing no further ``Action``s
///   8. The ``Instrumentation.Store.didProcessEvents`` callback is called
///   9. The ``Instrumentation.Store.willChangeState`` callback is called
///   10. The ``Store.state.value`` is updated
///   11. The ``ViewStore`` is updated with the ``Store.state``s new value
///   12. The ``Instrumentation.ViewStore.willDeduplicate`` callback is called
///   13. The state is deduplicated
///   14. The ``Instrumentation.ViewStore.didDeduplicate`` callback is called
///   15. The ``Instrumentation.ViewStore.stateWillChange`` callback is called
///   16. The ``ViewStore.state`` value is updated
///   17. All subscribers to the ``ViewStore.state`` are updated with the new state value
///   18. The ``Instrumentation.ViewStore.stateDidChange`` callback is called
///   19. The ``Instrumentation.Store.didChangeState`` callback is called
///   20. The ``Instrumentation.Store.didSend`` callback is called
///   21. The ``Instrumentation.ViewStore.didSend`` callback is called
public class Instrumentation {
  public typealias Trigger = (EventInfo) -> Void

  /// Container for the information that will be provided to tracking/instrumentation implementations.
  public struct EventInfo: CustomStringConvertible {
    internal init(type: String, action: String = "", tags: [String: String] = [:]) {
      self.type = type
      self.action = action
      self.tags = tags
    }

    /// The Swift type of object that is operating. This will generally be of the type `Store<State, Action>` or
    /// `ViewStore<State, Action>` with the `State` and `Action` types properly filled in. With this information it
    /// _should_ be possible to identify which ``Store`` or ``ViewStore`` (or other type) is operating.
    public let type: String

    /// A ``String`` generated for the ``Action`` that was sent, when available. There are operations that may not have
    /// an ``Action`` available and so this may be an empty string. The value is generated using ``String(describing:)``
    /// and so is dependent on the Swift runtime metadata. If that metadata is removed in some way then this value will
    /// be empty most likely.
    public var action: String

    /// A dictionary of tags that the library thinks are valuable to include in the tracking/instrumentation. There is
    /// obviously no requirement to use these, but they are there just in case.
    public var tags: [String: String]

    public var description: String {
      guard !action.isEmpty else {
        return "\(type)"
      }

      return "\(type): \(action)"
    }
  }

  public init(viewStore: Instrumentation.ViewStore? = nil, store: Instrumentation.Store? = nil) {
    self.viewStore = viewStore
    self.store = store
  }

  public static var shared: Instrumentation = .noop

  /// Tracking/instrumentation hooks that operate only within the context of ``ViewStore`` objects.
  public struct ViewStore {
    public init(willSend: @escaping Trigger, didSend: @escaping Trigger, willDeduplicate: @escaping Trigger, didDeduplicate: @escaping Trigger, stateWillChange: @escaping Trigger, stateDidChange: @escaping Trigger) {
      self.willSend = willSend
      self.didSend = didSend
      self.willDeduplicate = willDeduplicate
      self.didDeduplicate = didDeduplicate
      self.stateWillChange = stateWillChange
      self.stateDidChange = stateDidChange
    }

    /// Called _before_ the ``ViewStore.send`` handles the action.
    let willSend: Trigger
    /// Called  _after_ the ``ViewStore.send`` has completed handling the action.
    let didSend: Trigger
    /// Called _before_ the ``ViewStore`` attempts to deduplicate the old and new states. It is expected that for every
    /// ``willDeduplicate`` there will be a matching ``didDeduplicate``.
    /// Note: This may _not_ be called in every case. Because the deduplication implementation uses the
    /// ``Publisher.removeDuplicates`` method, this trigger will not be called on the _first_ state value (because there
    ///  is no old/new pair to compare).
    let willDeduplicate: Trigger
    /// Called _after_ the ``ViewStore`` has completed deduplicating the old and new states. It is expected that for
    /// every ``willDeduplicate`` there will be a matching ``didDeduplicate``.
    /// Note: This may _not_ be called in every case. Because the deduplication implementation uses the
    /// ``Publisher.removeDuplicates`` method, this trigger will not be called on the _first_ state value (because there
    ///  is no old/new pair to compare).
    let didDeduplicate: Trigger
    /// Called _before_ the ``ViewStore.state`` is updated with the new value.
    let stateWillChange: Trigger
    /// Called _after_ the ``ViewStore.state`` is updated with the new value.
    let stateDidChange: Trigger
  }

  /// Tracking/instrumentation hooks that operating only within the context of ``Store`` objects.
  public struct Store {
    public init(willSend: @escaping Instrumentation.Trigger, didSend: @escaping Instrumentation.Trigger, willChangeState: @escaping Instrumentation.Trigger, didChangeState: @escaping Instrumentation.Trigger, willProcessEvents: @escaping Instrumentation.Trigger, didProcessEvents: @escaping Instrumentation.Trigger) {
      self.willSend = willSend
      self.didSend = didSend
      self.willChangeState = willChangeState
      self.didChangeState = didChangeState
      self.willProcessEvents = willProcessEvents
      self.didProcessEvents = didProcessEvents
    }

    /// Called _before_ the ``Store.send`` has begun handling the action.
    let willSend: Trigger
    /// Called _after_ the ``Store.send`` has completed handling the action. This may include multiple instances of
    /// ``will|didChangeState`` and ``will|didProcessEvents`` pairs, and potentially further calls to the
    /// ``Instrumentation.ViewStore`` and ``Instrumentation.Store`` functions.
    let didSend: Trigger
    /// Called _before_ the ``Store.state.value`` is updated.
    let willChangeState: Trigger
    /// Called _after_ the ``Store.state.value`` is updated.
    let didChangeState: Trigger
    /// Called _before_ the ``Store`` handles any individual action that has been enqueued. This may include actions
    /// that have been returned via an ``Effect`` out of a ``Reducer`` that are synchronous or even results of ``Effects``
    ///  that were long running and just happened to complete while this ``Store`` was clearing the queue.
    let willProcessEvents: Trigger
    /// Called _after_ the ``Store`` has completed handling an individual action.
    let didProcessEvents: Trigger
  }

  let viewStore: ViewStore?
  let store: Store?
}

extension Instrumentation {
  static let noop = Instrumentation()
}
