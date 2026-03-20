# Abstract Synthesizer - Architecture Overview

> **📋 Navigation**: [Main README](../README.md) | **Overview** | [Usage Guide](usage.md) | [Examples](../examples/)

Abstract Synthesizer is a Ruby framework for creating **declarative, verifiable configuration DSLs**. This document explains the core architecture, design principles, and technical implementation details.

## 🎯 Core Concepts

### **Synthesizer**
The main orchestrator that processes DSL blocks and builds configuration manifests. It uses Ruby's `method_missing` to dynamically handle resource definitions and field assignments.

### **Manifest** 
An immutable, hierarchical data structure (Ruby Hash) representing your declarative configuration. Manifests are:
- **Verifiable**: Can be inspected and validated
- **Comparable**: Enable drift detection
- **Serializable**: Convert to YAML, JSON, ENV files, etc.

### **Resource Keys**
A predefined vocabulary of allowed resource types (e.g., `[:server, :database, :cache]`). This provides:
- **Type safety**: Prevent typos and invalid resources
- **Domain modeling**: Express your specific configuration domain
- **Validation**: Catch errors at declaration time

### **Bury Pattern**
A utility for deep hash assignment that enables natural nesting:
```ruby
hash.bury(:server, :web, :production, :host, 'example.com')
# Creates: { server: { web: { production: { host: 'example.com' } } } }
```

## Architecture Diagram

```mermaid
graph TD
    A[User DSL Input] --> B{AbstractSynthesizer};
    B -- "method_missing calls" --> C[abstract_method_missing];
    C -- "Validates method/args" --> D{Validation Logic};
    D -- "Raises Errors" --> E[Custom Errors];
    C -- "Builds nested hash" --> F[Bury Module (extends Hash)];
    F --> G[Manifest (Ruby Hash)];
    B -- "Returns" --> G;

    subgraph SynthesizerFactory
        H[create_synthesizer] --> B;
    end
```

## How it Works

1.  **Initialization**: A `Synthesizer` instance is created, optionally via the `SynthesizerFactory`, which injects the allowed `keys` for the DSL.
2.  **DSL Evaluation**: The `synthesize` method evaluates a Ruby block or string. Inside this context, method calls are intercepted.
3.  **Dynamic Method Handling**: The `method_missing` method (overridden in `AbstractSynthesizer` or dynamically defined by `SynthesizerFactory`) delegates to `abstract_method_missing`.
4.  **Validation**: `abstract_method_missing` validates the called method against the allowed `keys` and checks argument counts.
5.  **Manifest Building**: Based on the method and arguments, the synthesizer uses the `bury` method (provided by the `Bury` module) to insert data into the `translation[:manifest]` hash, creating nested structures as needed.
6.  **Result**: The final `manifest` hash represents the structured configuration defined by the DSL.

---

## 🔗 Related Documentation

- **[Usage Guide](usage.md)** - Learn how to use Abstract Synthesizer effectively
- **[Examples](../examples/)** - See real-world applications across different domains
- **[Main README](../README.md)** - Project overview and getting started

## 💡 Next Steps

1. Read the [Usage Guide](usage.md) for detailed implementation patterns
2. Explore [Examples](../examples/) to see Abstract Synthesizer in action
3. Check out the [API Reference](../lib/) for implementation details
