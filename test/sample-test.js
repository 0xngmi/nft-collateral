const { expect } = require("chai");

describe("Greeter", function () {
  it("create, lend and repay")

  it("can't call repay after rug()")

  it("can't call rug() before deadline")

  it("if total eth borrowed surpasses borrowCeiling, no tokens are distributed to previous owner and supply is set correctly")

  it("if isERC721 is wrong transactions fail")

  it("transfer of 0 is ok")

  it("can't call sweepFractionalTokens() with 0 amount")

  it("if isERC721 is wrong then contract reverts")

  it("mintRuggedTokens() works")

  it("can't mintRuggedTokens() that don't exist")

  it("can't mintRuggedTokens() twice")

  it("Should return the new greeting once it's changed", async function () {
    const Greeter = await ethers.getContractFactory("Greeter");
    const greeter = await Greeter.deploy("Hello, world!");
    await greeter.deployed();

    expect(await greeter.greet()).to.equal("Hello, world!");

    const setGreetingTx = await greeter.setGreeting("Hola, mundo!");

    // wait until the transaction is mined
    await setGreetingTx.wait();

    expect(await greeter.greet()).to.equal("Hola, mundo!");
  });
});
