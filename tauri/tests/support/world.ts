import { setWorldConstructor, World } from "@cucumber/cucumber";

class TauriUIWorld extends World {}

setWorldConstructor(TauriUIWorld);
