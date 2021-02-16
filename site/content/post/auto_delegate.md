---
title: "✨ Announcing AutoDelegate: Java code generation that makes composition easy!"
date: 2021-02-16T11:12:45-04:00
draft: false
tags: ["effective-java", "api-design", "composition", "delegation", "JSR-269", "Java"]
categories: ["Architecture"]
author: "Ryan Dens"
---

### Summary
For those without the time to read the full article, the "tl;dr" is 
- We should favor composition to inheritance
- We should leverage code generation tooling to reduce boilerplate, maintenance cost, and encourage best practices
- [AutoDelegate](https://github.com/ryandens/auto-delegate) is a project which does both and is available on Maven Central!

### The Problem
Classical inheritance is the most widely used and hated abstraction in programming languages. 
It starts small but often results in complex and hard-to-understand behavior in large software projects. It makes the task of refactoring code orders of magnitude riskier. Brian Goetz, 
Java Language Architect at Oracle says "my one-sentence summary of the history of programming languages is, 'we have one good trick that works.' And that trick is composition.". Josh Bloch,
in Effective Java Item 18, tells us "Favor composition over inheritance". This idea is about as much consensus on a topic that programmers are capable of developing, as we love to debate the nuances of each approach. So why is inheritance so common? In my opinion, its because composition
has the opportunity to be much more verbose than inheritance, so it's easier for our minds to first jump to an inheritance hierarchy rather than composing the behavior among multiple distinct
classes and interfaces with clear separation of responsibility. 

Even though we know that code will be read thousands of times more than it will be written or modified in any meaningful way, it's challenging to think that way when writing code. As we know, 
 [clear is better than clever](https://dave.cheney.net/2019/07/09/clear-is-better-than-clever) Also, 
 much of the code that's being written is "boring" or "repetitive" to write. Luckily, we have robots! 🤖


 ### The Inspiration
 I'm far from the first person to recognize this problem. Google's [auto](https://github.com/google/auto) 
 project has an excellent track record for using code generation to reduce boilerplate in doing things
 "the right way". Indeed, AutoDelegate leverages some utilities exposed by auto, so shoutout to the maintainers for helping lower the barrier to entry for writing annotation processors!


 The primary inspiration for AutoDelegate was the Kotlin language feature called 
 [delegation](https://kotlinlang.org/docs/delegation.html). I have no doubts that this is a fundamentally superior approach to any annotation processing and code generation approach could hope to achieve. 
 However, there are lots of Java projects out there that have no desire or bandwidth to integrate Kotlin into their projects. Making delegation more accessible in pure Java should help developers write abstractions on the JVM that work and can be maintained.


 ### The Solution 
 My solution to this problem is [AutoDelegate](https://github.com/ryandens/auto-delegate)! This project 
 releases two components to Maven Central:
 
 1. [auto-delegate-annotations](https://search.maven.org/artifact/com.ryandens/auto-delegate-annotations/0.1.0/jar) for decorating your classes with the metadata necessray to generate the delegation boilerplate
 1. [auto-delegate-processor](https://search.maven.org/artifact/com.ryandens/auto-delegate-processor/0.1.0/jar) provides a `javax.annotation.processing.Processing` implementation that looks for classes annotated with `auto-delegate-annotations` and generates classes that enable the use of composition!

The `Processor` generates abstract classes that compose an instance of an interface specified on the annotation and automatically forward 
to it.


### Example

Show me the code! The goal of this library is to encourage the use of composition over inheritance as described by Effective Java Item 18 "Favor
composition over inheritance". In the section of the book, Bloch describes an `InstrumentedSet`that counts the number of
items added to it. To accomplish this, Bloch creates an abstract implementation of `java.util.Set`
called `ForwardingSet` that simply composes a `java.util.Set` instance and forwards all calls to it. This allows Bloch
to write the `InstrumentedSet` in a less verbose manner, by extending `ForwardingSet` and overriding the "add" related
methods for instrumentation purposes. This is a great solution in the context of Java, but Kotlin lowers the cognitive
barrier of using composition by making it less verbose to do so. In Kotlin, the need for a `ForwardingSet`is obviated by
the [delegation language feature](https://kotlinlang.org/docs/delegation.html) discussed above. The `InstrumentedSet` can be 
written concisely without relying on writing a `ForwardingSet` like:

```kotlin 

 class InstrumentedSet<E>(val inner: MutableSet<E>) : MutableSet<E> by inner {
     var count: Int = 0

     override fun add(element: E): Boolean {
         count++
         return inner.add(element)
     }

     override fun addAll(elements: Collection<E>) : Boolean {
         count += elements.size
         return inner.addAll(elements)
     }
 }
```

AutoDelegate strives to enable developers in the same fashion by generating abstract `Forwarding` classes that
delegate to the inner composed instance. An equivalent `InstrumentedSet` implementation written with `AutoDelegate` is

```java

@AutoDelegate(Set.class)
public final class InstrumentedSet<E> extends AutoDelegate_InstrumentedSet<E> implements Set<E> {
    private int addCount;

    public InstrumentedSet(final Set<E> inner) {
        super(inner);
        this.addCount = 0;
    }

    @Override
    public boolean add(final E t) {
        addCount++;
        return super.add(t);
    }

    @Override
    public boolean addAll(final Collection<? extends E> c) {
        addCount += c.size();
        return super.addAll(c);
    }

    /**
     * @return the number of times a caller has attempted to add an item to this set
     */
    public int addCount() {
        return addCount;
    }
}
```

While this is not as concise as the Kotlin implementation, it generates a class called `AutoDelegate_InstrumentedSet` in
the same package as the declaring class. The declared class can then extend the generated class and call `super`
APIs where appropriate, only overriding methods that are relevant to the implementation
