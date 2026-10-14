Feature: Stable Hermes releases remain updateable and packaged
  The accepted L1/L2 contract lives in the homelab Hermes agent delivery plan.
  Updater scenarios bind to checks.x86_64-linux.updater-mutation-only.
  Package acceptance additionally requires the owner build and native version recipes.

  Scenario Outline: Stable and legacy release tags update only the upstream input
    Given an isolated copy of the current source and lock files
    When the updater targets <tag>
    Then the source URL references <tag>
    And Nix is called exactly once with "flake update hermes-agent-src"
    And the auto-tag workflow accepts <tag>
    And the actual package provenance predicate accepts <tag> in Nix
    Examples:
      | tag          |
      | v0.21.7      |
      | v2099.1.1    |
      | v2099.1.1.2  |
      | v0.21.7.1    |

  Scenario: Check-only leaves source files unchanged
    When a stable release is checked without mutation
    Then an available update returns status 1
    And both files remain byte-identical with zero Nix calls

  Scenario Outline: Invalid releases cannot mutate source or produce tags
    When the updater targets <tag>
    Then it returns status 2 with both files byte-identical and zero Nix calls
    And the auto-tag workflow rejects <tag>
    And the actual package provenance predicate rejects <tag> in Nix
    Examples:
      | tag               |
      | 0.21.7            |
      | v0.21             |
      | v0..7             |
      | v0.21.7-rc.1      |
      | v0.21.7+build     |
      | v0.21.7junk       |
      | v0.21.7.1.2       |
      | v2099.1.1-rc.1    |
      | v2099.1.1.2junk   |

  Scenario: A partially written failed lock update restores both files
    Given Nix changes the lock file and then exits nonzero
    When the updater targets a stable release
    Then both original files are restored byte-for-byte
    And Nix was called exactly once with "flake update hermes-agent-src"

  Scenario: The requested upstream release is packaged
    Then the original upstream lock ref is "v0.21.7"
    And the owner base package builds
    And the native CLI reports release "0.21.7"
    And the existing smoke and OCI module checks pass

  Scenario: Immutable package provenance drives every native identity surface
    Given the stable release tag and revision in the upstream input lock
    Then the installed package carries upstream's canonical Nix provenance schema
    And native CLI and shared code identity report that version and revision
    And missing, wrong-version and wrong-revision provenance cannot satisfy acceptance
    And an extras variant reads the same common installed package identity
    And checks use isolated disposable homes without a source Git checkout
