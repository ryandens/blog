---
title: "✔️ How to Adopt Consumer-Driven Contracts Tests"
date: 2020-05-31T10:43:00-04:00
draft: true
---


Testing web APIs is hard. As an industry, we've tackled this in many different ways - ranging from testing nothing at all to every aspect of both the client and the server code in one fell swoop.  One way to test web APIs in a way that minimizes non-deterministic test failures, gives developers confidence that their systems are working, and empowers teams to solve the problems in the systems they own is using consumer-driven contract tests. I'll show you how to identify if contract tests are for you and if so, how to start using them at work.

This article will (hopefully) be interesting to you if you're currently maintaining, extending, or building a system of integration tests between two services that communicate via messages (e.g. an HTTP request). The perspective I come at this from is primarily testing a REST API and the client code responsible for sending it HTTP requests.  Before reading this, you should understand the basics of HTTP and REST semantics.

## Step 1: Identify if there is a challenge with your current testing approach

Nearly every approach to testing has its place. The answer to every question of the form, "Should I use \<A> or \<B>?" is "It depends". There is a wealth of counterexamples to any technical approach as to why it shouldn't be done. However, I'll call out a few challenges I identified in the situation I encountered. 

The biggest red flag with a large integration testing system is if that system has regular non-deterministic failures which are hard to diagnose and most frequently false positives. The origin of these irregularities might be from the System(s) Under Test (S.U.T.), from the system designed to test them, or both. 

Another red flag is that significant bugs that should or would have been caught by the system are still making it to production. Either there is "insufficient" test coverage or the testing is happening at the wrong place and time. The idea of insufficient test coverage may sound laughable to you - after all, this system already tests so much! The reality is that many of these testing systems spend a lot of time and energy testing code that has already been tested in more direct and easier to debug ways. There are often large swaths of code that remains unexercised or underutilized, some of which may be prohibitively challenging to test directly. 

The final and most important litmus test is if everyone hates the integration testing system. Working with unreliable software is no fun. Developers like to build things they can be proud of. If the system that is supposed to verify the quality of the production code being written by developers suffers from any of the above challenges, it's going to be very hard to feel proud of anything they build. As a result, developers will avoid adding test cases that most likely deserve to be there and the quality of your software will degrade. 


## Step 2: Determine if consumer-driven contracts solve the challenges you've identified

One of the most important challenges I was interested in solving was eliminating non-deterministic failures that are hard to diagnose. 

If the source of the non-determinism is in the system designed to test your services, then the easiest thing to do (may) be to use infrastructure that is maintained and actively used by others. This lets you and your team focus on the real problems facing you, not re-inventing the wheel with the world's one millionth testing system.

If the source of the non-determinism is in the system(s) under test, then it is generally best to test the functionality of these two systems independently. This generally works out very well, because irregularities in testing behavior can be tracked down more quickly by the correct people. 

However, this leaves us with a crucial gap: making sure the two systems work together. Making sure that these two services work properly together doesn't necessarily mean standing up both of these services and testing their behavior end to end at the same time.

Consumer-driven contract tests allow us to test the code responsible for sending a message in one service (the consumer), capturing it, and verifying that it is correct. Later, we can replay that message to the other service (the provider) and make sure that it understands it. 

While this doesn't make any problems in the systems under test go away, it does make the origin more clear, easier to track down, and harder to ignore. If the source of the non-determinism is the consumer, you'll see inconsistent test failures when generating the contract, as part of the contract generation is making sure it stays the same. If the source of the non-determinism in the provider, you'll have a reproducible inconsistency with the captured message, whose contents are known.


## Step 3. Pick a tool
The most efficient way to adopt this style of testing is to make use of an existing tool. My focus is on testing two services that interact via HTTP and I happen to be on a team that writes Java code responsible for consuming responses from a web API. The API provider is a different team that also happens to be written in Java, but I also knew there are other consumers written in Go, Ruby, Node, Python, and C# that face similar challenges as my team. I wanted to make sure we picked a tool that could reduce the overhead for subsequent teams to adopt consumer-driven contracts, so choosing a tool that works effectively with all these languages was a priority. After some research, I decided to go with [Pact](https://pact.io). I highly recommend it, but your use case may justify something different. I'll give my examples here using their tooling. 

## Step 4 Pick an existing API to test
I think its easiest to pick an existing API to try this out with, as you likely already have reasonable confidence that the consumer and the provider code are working properly. I'll give an example here of an API defined using JAX-RS and a command-line tool that interacts with that API.




### API Provider
```java
import com.github.ryandens.provider.messages.CoffeeOrder;
import com.github.ryandens.provider.messages.Receipt;
import javax.ws.rs.Consumes;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.Produces;
import javax.ws.rs.core.MediaType;

@Path("/coffee")
public final class CoffeeService {

  private final PriceService priceService;

  public CoffeeService(final PriceService priceService) {
    this.priceService = priceService;
  }

  @POST
  @Consumes(MediaType.APPLICATION_JSON)
  @Produces(MediaType.APPLICATION_JSON)
  public Receipt makeOrder(final CoffeeOrder coffeeOrder) {
    // business logic
    final double price = priceService.calculate(coffeeOrder);

    return Receipt.of(coffeeOrder, price);
  }
}
```


### API Consumer


```java

import com.fasterxml.jackson.databind.ObjectMapper;
import com.github.ryandens.consumer.messages.CoffeeOrder;
import com.github.ryandens.consumer.messages.Receipt;
import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;

public final class Main {

  private static final HttpClient httpClient = HttpClient.newHttpClient();
  private static final ObjectMapper objectMapper = new ObjectMapper();

  /**
   * Entry point of the API Consumer application, responsible for starting and stopping resources
   */
  public static void main(final String[] args) {
    final Receipt receipt;
    try {
      receipt =
          sendOrder(
              CoffeeOrder.of(CoffeeOrder.Size.LARGE, CoffeeOrder.Bean.CATURRA),
              "http://ryandens.com");
    } catch (InterruptedException | IOException e) {
      throw new RuntimeException(e);
    }
    System.out.println("receipt: " + receipt.toString());
  }

  static Receipt sendOrder(final CoffeeOrder coffeeOrder, final String hostName)
      throws InterruptedException, IOException {
    final var request =
        HttpRequest.newBuilder(URI.create(hostName + "/coffee"))
            .header("Content-Type", "application/json")
            .POST(
                HttpRequest.BodyPublishers.ofByteArray(objectMapper.writeValueAsBytes(coffeeOrder)))
            .build();

    final var response = httpClient.send(request, HttpResponse.BodyHandlers.ofString());
    if (response.statusCode() == 200) {
      return objectMapper.readValue(response.body(), Receipt.class);
    } else {
      throw new RuntimeException("Unexpected response code: " + response.statusCode());
    }
  }
}
```

## Step 5: Generate a contract using the consumer

This might require you to refactor your code slightly, but generally speaking, the consumer code can be unit tested quite easily using integrations offered by [pact-jvm](https://github.com/DiUS/pact-jvm/). Note that similar integrations exist for other languages and can found in the [Pact docs](https://docs.pact.io/implementation_guides).


```java
import au.com.dius.pact.consumer.MockServer;
import au.com.dius.pact.consumer.dsl.PactDslWithProvider;
import au.com.dius.pact.consumer.junit5.PactConsumerTestExt;
import au.com.dius.pact.consumer.junit5.PactTestFor;
import au.com.dius.pact.core.model.RequestResponsePact;
import au.com.dius.pact.core.model.annotations.Pact;

@ExtendWith(PactConsumerTestExt.class)
@PactTestFor(providerName = "CoffeeService")
final class CoffeeClientPactTest {

    @Pact(consumer = "CoffeeClient")
  RequestResponsePact sendCoffeeOrder(final PactDslWithProvider builder) {
    return builder
        .uponReceiving("Send a Coffee Order")
        .path("/coffee")
        .body("{\"size\": \"LARGE\", \"bean\":\"HAZELNUT\"}")
        .headers(Collections.singletonMap("Content-Type", "application/json"))
        .method("POST")
        .willRespondWith()
        .body(
            new PactDslJsonBody()
                .decimalType("price", 3.50)
                .object("coffeeOrder")
                .stringValue("size", "LARGE")
                .stringValue("bean", "HAZELNUT")
                .closeObject())
        .headers(Collections.singletonMap("Content-Type", "application/json"))
        .status(200)
        .toPact();
  }


  @Test
  @PactTestFor(pactMethod = "sendCoffeeOrder")
  void testSendCoffeeOrder(final MockServer mockServer) {
    final var coffeeOrder = CoffeeOrder.of(CoffeeOrder.Size.LARGE, CoffeeOrder.Bean.HAZELNUT);

    final Receipt receipt;
    try {
      receipt = Main.sendOrder(coffeeOrder, mockServer.getUrl());
    } catch (InterruptedException | IOException e) {
      throw new AssertionError(e);
    }

    assertEquals(3.50, receipt.price());
    assertEquals(coffeeOrder, receipt.coffeeOrder());
  }
}
```

The above snippet delves a bit into the specifics of Pact, but from my understanding, this is going to be relatively similar for any contract testing tool. In the above snippet, we used the pact-jvm DSL to create a mock HTTP server in the method `sendCoffeeOrder`. This mock HTTP server knows how to do one thing, response to the request we described to it. Then, in the test method `testSendCoffeeOrder`, we exercise our client code to send a request to the mock HTTP server we configured. If the code we exercise sends a slightly different HTTP request, the test will fail. If not, it will pass. 

## Step 6: Verify a contract using the provider
Our test passing in step 5 gives us no confidence that our client and consumer will communicate effectively. It did, however, capture a description of how the client will behave. Now, we need to verify that behavior is correct. The only way we can do that is by testing the API provider. First, we'll stand up our API provider locally. Then, we'll use some more pact tooling to use the contract generated in step 5 to replay the HTTP request and verify the response is the same. 

There are a few different tools available for this, but I find that the JUnit extension is most flexible without requiring you to do any additional scripting to make sure resources are configured correctly

```java
import au.com.dius.pact.provider.junit.Provider;
import au.com.dius.pact.provider.junit.loader.PactFolder;
import au.com.dius.pact.provider.junit5.PactVerificationContext;
import au.com.dius.pact.provider.junit5.PactVerificationInvocationContextProvider;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.TestTemplate;
import org.junit.jupiter.api.extension.ExtendWith;

@Provider("CoffeeService")
@PactFolder("../consumer/build/pacts/")
final class ContrastVerificationTest {

  @BeforeAll
  static void beforeAll() {
    final var httpServer = Main.createHttpServer(false, 8080);
    httpServer.start();
  }

  @TestTemplate
  @ExtendWith(PactVerificationInvocationContextProvider.class)
  void pactVerificationTestTemplate(final PactVerificationContext context) {
    context.verifyInteraction();
  }
}
```

It's worth noting that while in this example we opted to simply pull contracts from a local directory, in most enterprise use cases you'll find using a 
[Pact Broker](https://docs.pact.io/pact_broker) helps with projects that might not be in the same repository. The project is open-sourced, so you can self-host it. However, [Pactflow](https://pactflow.io/) offers a hosted solution with additional enterprise features like SSO, token
authentication, and webhooks, which can help reduce any friction in your adoption process. Pactflow was founded by the creators of all the open-source software we utilize in these tests. So, by supporting Pactflow, you can support their entire open-source platform as well.  

## Step 7. Tie this work to business value

 Driving technical initiatives and prioritizing the reduction of technical debt is challenging in any organization. However, associating and tying that technical debt to business value can offer a compelling story. 
 
 Incorporating new testing strategies with feature requests involving a change to the way two systems communicate is a great way to try this out on a larger scale. Rather than embarking right away on tearing down your integration testing system discussed earlier, simply stop investing in it (for now) when you build new features. Using consumer-driven contract tests alongside the demos that frequently occurs as part of developing a new feature will give you the confidence that these tests are guaranteeing the quality of the feature. 

 Another great way to adopt contract tests is to look for a common theme of bug reports. If there are frequent bug reports as a result of two systems not interacting properly, contract tests will allow you to fill those gaps faster. Often, it is non-trivial and/or impossible to reproduce the edge cases or race conditions that led to the bug in these two systems interacting as they should.

 Once you've taken one or both of these paths as a mechanism to prove (or disprove) the business value of contract tests for your systems, many or all pieces of the large integration testing system will be classified as "legacy". Use data to show your stakeholders how much this system is holding back teams at your company. Thinking about the "happy path" of this testing system is helpful, but I think there is much more compelling data in comparing the average time to failure with a large integration testing system versus contract tests. Due to the nature of most of these large integration testing systems, developers tend to run these tests less frequently than their unit testing suite. Sometimes, these testing systems only get run before releasing to production. By incorporating contract tests using tools like Pact, the feedback loop for developers will be much faster. This means that if a developer makes a change that causes the expectations of a contract to change, they'll likely discover it mere minutes after introducing it, rather than the hours, days, or weeks that can span between a successful run of an unreliable test system. 


 ## Next steps
 Testing web APIs is hard, but it doesn't have to be. This guide was designed to help you think about the adoption of consumer-driven contracts and if it's right for you. Ultimately, you're going to know best when you've tried it out. All of the code in this guide was synthesized into a working example project on my Github account, [ryandens/consumer-driven contracts-example](https://github.com/ryandens/consumer-driven-contracts-example). Try messing with the code samples I gave here. Break something, add a test that I'm missing, or add a new endpoint! I welcome you to send PRs to my repository or fork and make changes that make sense for demonstrations for your team. If you have questions or disagree with something I said, feel free to reach out! I'm always happy to chat about testing strategies and ideologies. You can find me on [Twitter](https://twitter.com/RyanDens1) and [Keybase](https://keybase.io/rdens).
 
 Luckily, there's a thriving community out there looking to help out. Here are some great resources to get you started:
 
 1. [ContractTest](https://martinfowler.com/bliki/ContractTest.html) by Martin Fowler, a more formal definition than what I give above but a super helpful foundation
 1. [Consumer-Driven Contracts: A Service Evolution Pattern](https://martinfowler.com/articles/consumerDrivenContracts.html) by Ian Robbinson. This goes into the specifics of why Pact and many other tools chosen to optimize for the "consumer-driven" experience
 1. [Pact Introduction](https://docs.pact.io/) terms you should be familiar with after reading this guide, but this is a great reference for friendly definitions of important concepts
 1. [Pact 5-minute guide](https://docs.pact.io/5-minute-getting-started-guide) a quick way to write and verify your first contract test, all from your browser!
 1. [Effective Pact Setup guide aka Pact Nirvana](https://docs.pact.io/pact_nirvana). If you decide to introduce contracts, this guide will tell you how to do it right. Follow it, you won't regret it.
