---
title: "👷‍♀️ How to build a typesafe heterogenous container with Dagger"
date: 2020-08-10T07:39:55-04:00
tags: ["dagger", "effective-java", "api-design", "DI", "dependency-injection", "JSR-330", "Java"]
categories: ["Architecture"]
author: "Ryan Dens"
draft: true
---


Typesafe heterogenous containers allow us to group objects of arbitrary types while maintaining the ability to access them in a typesafe manner. Dagger is a compile-time dependency injection tool which reduces the boilerplate in object initialization. Dagger provides incredibly useful functionality on top of the 
JSR-330 dependency injectyion specification which automatically builds other containers, like sets or lists, that contain objects which Dagger already knows how to instantiate. I'll demonstrate how to leverage existing Dagger mechanisms to populate a typesafe heterogenous contanier with objects that Dagger knows how to instantiate. 

## Prerequisities
Prior to reading this, you should have some familiarity with the following:
- Effective Java Item 33: Consider typesafe heterogenous containers. If you're unfamiliar and don't have access to the book, you can read [this article](https://www.informit.com/articles/article.aspx?p=2861454&seqNum=8).
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

Next, we define a Dagger [Module](https://dagger.dev/api/latest/dagger/Module.html) for each of these services which is responsible for informing Dagger to put the initialized objects into a `Map` when asked.

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

Finally, we define a Dagger [Component](https://dagger.dev/api/latest/dagger/Component.html) which can be used to access the `Map` once its built.

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
Separating the responsibility of instantiating the services and populating the `Map` from the client code responsible for accessing it and using the business logic is definitely ideal and is generally the reason why tools like Dagger exist. However, the way we must access these services is not ideal. We have no way to mandate that an `Entry`'s key is of the same type as the value it maps to. Luckily, this is why typesafe heterogenous containers exist!


## Using a typesafe heterogenous container without Dagger
Before we use Dagger to build a typesafe heterogeneous container, we must first understand how we would build one without Dagger. Below is an example implementation of a typesafe heterogenous container and some client code which reads and writes into it.

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


## Building a typesafe heterogenous container with Dagger
In order to guarantee that access to our container with a certain key will always correspond to a value of the same type,