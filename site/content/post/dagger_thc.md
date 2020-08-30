---
title: "👷‍♀️ How to build a typesafe heterogeneous container with Dagger"
date: 2020-08-31T08:00:00-04:00
tags: ["dagger", "effective-java", "api-design", "DI", "dependency-injection", "JSR-330", "Java"]
categories: ["Architecture"]
author: "Ryan Dens"
draft: false
---


Typesafe heterogeneous containers allow us to group objects of arbitrary types while maintaining the ability to access them in a typesafe manner. Dagger is a compile-time dependency injection tool which reduces the boilerplate in object initialization. Dagger provides incredibly useful functionality on top of the 
JSR-330 dependency injection specification which automatically builds other containers, like sets or lists, that contain objects which Dagger already knows how to instantiate. I'll demonstrate how to leverage existing Dagger mechanisms to populate a typesafe heterogeneous container with objects that Dagger knows how to instantiate. 

## Prerequisities
Prior to reading this, you should have some familiarity with the following:
- Effective Java Item 33: Consider typesafe heterogeneous containers. If you're unfamiliar and don't have access to the book, you can read [this article](https://www.informit.com/articles/article.aspx?p=2861454&seqNum=8).
- Dagger 2's support of standard `javax.inject` annotations as described in the [Dagger developer guide](https://dagger.dev/dev-guide/).
- Dagger 2's multibinding support as described in their [documentation](https://dagger.dev/dev-guide/multibindings).

## Using Dagger multibindings to build a container without type safety

First, we must define the classes which we want to put into our container! We give each of these a no-args constructor which is annotated with `javax.inject.Inject` so that Dagger knows how to instantiate them.

```java
package com.github.ryandens.dagger.thc.a;

import javax.inject.Inject;

public final class ServiceA {

  @Inject
  ServiceA() {}

  public String customServiceAMessage() {
    return "Hello from service A!";
  }
}
```

```java
package com.github.ryandens.dagger.thc.b;

import javax.inject.Inject;

public final class ServiceB {

  @Inject
  ServiceB() {}

  public String customServiceBMessage() {
    return "Hello from service B!";
  }
}
```

Next, we define Dagger [Modules](https://dagger.dev/api/latest/dagger/Module.html) for each of these services which are responsible for informing Dagger to put the initialized objects into a `Map` when asked.

```java
package com.github.ryandens.dagger.thc.a;

import dagger.Module;
import dagger.Provides;
import dagger.multibindings.ClassKey;
import dagger.multibindings.IntoMap;

@Module
public final class ModuleA {

  @Provides
  @IntoMap
  @ClassKey(ServiceA.class)
  static Object provideServiceA(final ServiceA serviceA) {
    return serviceA;
  }
}
```


```java
package com.github.ryandens.dagger.thc.b;

import dagger.Module;
import dagger.Provides;
import dagger.multibindings.ClassKey;
import dagger.multibindings.IntoMap;

@Module
public final class ModuleB {

  @Provides
  @IntoMap
  @ClassKey(ServiceB.class)
  static Object provideServiceB(final ServiceB serviceB) {
    return serviceB;
  }
}
```

Finally, we define a Dagger [Component](https://dagger.dev/api/latest/dagger/Component.html) which can be used to access the `Map` once it's built.

```java

package com.github.ryandens.dagger.thc;

import com.github.ryandens.dagger.thc.a.ModuleA;
import com.github.ryandens.dagger.thc.b.ModuleB;
import dagger.Component;
import java.util.Map;

@Component(modules = {ModuleA.class, ModuleB.class})
public interface RootComponent {

  Map<Class<?>, Object> map();
}

```

However, any code which we use which accesses services put in this `Map` would not be typesafe. Each access to the `Map` would require checks to properly cast the object to the appropriate type. For example: 


```java
package com.github.ryandens.dagger.thc;

import com.github.ryandens.dagger.thc.a.ServiceA;
import com.github.ryandens.dagger.thc.b.ServiceB;

public final class Main {

    public static void main(final String[] args) {
        final var map = DaggerRootComponent.create().map();
        final Object value = map.get(ServiceA.class);

        // 🤞 we know what we're doing, suppress the unchecked cast warning!
        @SuppressWarnings("unchecked")
        final ServiceA serviceA = (ServiceA) value;
        System.out.println(serviceA.customServiceAMessage());

        // Or, safely cast and handle the class mismatch..somehow?
        final Object otherValue = map.get(ServiceB.class);
        if (otherValue instanceof ServiceB) {
            final ServiceB serviceB = (ServiceB) otherValue;
            System.out.println(serviceB.customServiceBMessage());
        } else {
            // oh no 🤯
            System.out.println("this is fine 🙃");
        }
    }
}
```
Separating the responsibility of instantiating the services and populating the `Map` from the client code responsible for accessing it and using the business logic is ideal and is generally the reason why tools like Dagger exist. However, the way we must access these services is not ideal. We have no way to mandate that an `Entry`'s key is of the same type as the value it maps to. Luckily, this is why typesafe heterogeneous containers exist!


## Using a typesafe heterogeneous container without Dagger
Before we use Dagger to build a typesafe heterogeneous container, we must first understand how we would build one without Dagger. Below is an example implementation of a typesafe heterogeneous container and some client code that reads and writes into it.

```java
public final class Container {

    private final Map<Class<?>, Object> container = new HashMap<>();

    public <T> void put(final Class<T> type, final T value) {
        container.put(type, value);
    }

    public <T> T get(final Class<T> type) {
        return type.cast(container.get(type));
    }
}
```

```java
public final class Main {

    public static void main(final String[] args) {
        final var container = new Container();
        container.put(ServiceA.class, new ServiceA());
        container.put(ServiceB.class, new ServiceB());
        final ServiceA serviceA = container.get(ServiceA.class);
        System.out.println(serviceA.customServiceAMessage());
        System.out.println(container.get(ServiceB.class).customServiceBMessage());
    }
}
```

The API for accessing these services is now much cleaner. However, we're now responsible for initializing these services and populating the container ourselves. While Dagger does provide a `@IntoMap` annotation, it does not yet provide an `@IntoTypesafeHeterogenousContainer`! If separating these responsibilities and reducing initialization boilerplate is important for your software, we can write a small amount of additional code, and modify some existing code, to build a bridge between our provided services and the container we want them to end up in.


## Building a typesafe heterogeneous container with Dagger
To guarantee that access to our container with a certain key will always correspond to a value of the same type, we must forge an association between the key and the value that is guaranteed to exist by the compiler at service registration time. This is now pretty easy to do thanks to the `Record` feature currently in preview in JDK 14.

```java
package com.github.ryandens.dagger.thc;

public record Registration<T>(Class<T> key, T value) {}
```
 
Now, we must change our dagger modules `ModuleA` and `ModuleB` to instead provide
a `Registration` for both `ServiceA` and `ServiceB`. We can do this quite easily by using a different multibinding annotation, `@IntoSet`. Now, these module classes look like this:

```java
package com.github.ryandens.dagger.thc.a;

import com.github.ryandens.dagger.thc.Registration;
import dagger.*;

@Module
public final class ModuleA {

  @Provides
  @IntoSet
  static Registration<?> provideRegistration(final ServiceA serviceA) {
    return new Registration<>(ServiceA.class, serviceA);
  }
}
```

```java
package com.github.ryandens.dagger.thc.b;

import com.github.ryandens.dagger.thc.Registration;
import dagger.*;

@Module
public final class ModuleB {

  @Provides
  @IntoSet
  static Registration<?> provideRegistration(final ServiceB serviceB) {
    return new Registration<>(ServiceB.class, serviceB);
  }
}
```

Now, the Dagger object graph knows how to build a `Set<Registration<?>>`. We definitively know that for each `Registration` in the `Set`, the type of `Registration.value()` must match the type parameter of the `Class` returned by `Registration.key()`. This is powerful because now we can reuse our `Container` implementation from before and populate it with service registrations using its typesafe API in a Dagger provider. I propose we add a `RootModule` class which is responsible for providing a `Container` instance populated with our services.

```java
package com.github.ryandens.dagger.thc;


import com.github.ryandens.dagger.thc.a.ModuleA;
import com.github.ryandens.dagger.thc.b.ModuleB;
import dagger.Module;
import dagger.Provides;
import java.util.Set;

@Module(includes = {ModuleA.class, ModuleB.class})
public final class RootModule {
  @Provides
  static Container provide(final Set<Registration<?>> registrations) {
    final var container = new Container();
    registrations.forEach(container::put);
    return container;
  }
}
```

Now, our `RootComponet` interface can discard its unsafe `Map<Class<?>, Object>` reference and instead provide a typesafe `Container` to its clients!

```java
package com.github.ryandens.dagger.thc;

import dagger.Component;

@Component(modules = {RootModule.class})
public interface RootComponent {

  Container container();
}
```

Now, our `Main` class can take advantage of both Dagger's boilerplate reduction and our `Container`'s type safety!

```java
package com.github.ryandens.dagger.thc;

import com.github.ryandens.dagger.thc.a.ServiceA;
import com.github.ryandens.dagger.thc.b.ServiceB;

public final class Main {

  public static void main(final String[] args) {
    final var container = DaggerRootComponent.create().container();
    final var serviceA = container.get(ServiceA.class);
    System.out.println(serviceA.customServiceAMessage());
    final ServiceB serviceB = container.get(ServiceB.class);
    System.out.println(serviceB.customServiceBMessage());
  }
}
```


## Modularization benefits
One of the strengths of using Dagger is its ability to help one modularize their codebase. We can add a new `ServiceC` class and we won't have to modify any of our existing code, we simply need to provide it into the `Set<Registration<?>>` using dagger. Similarly, our `Container` is not at all tied to our Dagger usage and can be re-used outside of that context as well. Each of our modules is independent of one another and only need to maintain a small API for service registration. 


## Takeaways 
We can do more with this as well, but I wanted to focus on the most basic way we can make Dagger and typesafe heterogeneous containers integrate well together. The complete example code is on my GitHub at [ryandens/dagger-typesafe-heterogeneous-container](https://github.com/ryandens/dagger-typesafe-heterogeneous-container). This project also includes a more complex usage example where `ServiceA` and `ServiceB` share a common interface with different parameterized types used on the interface. I hope to examine this more in-depth in a future blog post!

Theoretically, we could create a custom `@IntoTypesafeHeterogenousContainer` Dagger multibinding by creating a [Dagger Service Provider Interface Plugin](https://dagger.dev/dev-guide/spi)(https://dagger.dev/dev-guide/spi) which could be published as a library and consumed alongside Dagger to natively integrate your modules with a `Container` declared on the component. Building this wouldn't be trivial, but it is somewhere on my to-do list 😀. 

If you notice anything about my repository that could be more clear or better documented, please send me a pull request!