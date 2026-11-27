import "reflect-metadata";
import { Body, Controller, Get, Headers, HttpCode, Module, Post } from "@nestjs/common";
import { NestFactory } from "@nestjs/core";

class FixtureController {
  greet() {
    return "Hello from NestJS on Wasmer Edge";
  }

  describe() {
    return { framework: "nestjs" };
  }

  echo(body, probe) {
    return { body, probe };
  }
}

const routes = FixtureController.prototype;
Controller()(FixtureController);
Get()(routes, "greet", Object.getOwnPropertyDescriptor(routes, "greet"));
Get("json")(routes, "describe", Object.getOwnPropertyDescriptor(routes, "describe"));
Post("echo")(routes, "echo", Object.getOwnPropertyDescriptor(routes, "echo"));
HttpCode(200)(routes, "echo", Object.getOwnPropertyDescriptor(routes, "echo"));
Body()(routes, "echo", 0);
Headers("x-probe")(routes, "echo", 1);

class FixtureModule {}
Module({ controllers: [FixtureController] })(FixtureModule);

const app = await NestFactory.create(FixtureModule);
app.use((_request, response, next) => {
  response.setHeader("X-Fixture", "js-nestjs");
  next();
});
await app.listen(Number(process.env.PORT || 8080), process.env.HOST || "127.0.0.1");
