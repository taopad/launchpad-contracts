import { time, loadFixture, mine } from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import { LaunchpadFactory__factory, TokenMockup__factory } from "../typechain-types";


async function deployTokenFixture() {
  const [tokenOwner] = await ethers.getSigners();

  const token = await new TokenMockup__factory(tokenOwner).deploy();
  await token.deployed();

  // Fixtures can return anything you consider useful for your tests
  return { token, tokenOwner };
}

async function deployLaunchpadFixture() {

  const [, deployer, protocolFeeAddress] = await ethers.getSigners();

  const launchpadFactory = await new LaunchpadFactory__factory(deployer).deploy(protocolFeeAddress.address, 100);
  await launchpadFactory.deployed();
  
  return { launchpadFactory, deployer, protocolFeeAddress };
}

async function deployCoreProtocolFixture() {

  const { token, tokenOwner } = await loadFixture(deployTokenFixture);
  const { launchpadFactory, deployer, protocolFeeAddress } = await loadFixture(deployLaunchpadFixture);

  return { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress };

}

async function deployLaunchpad() {

  const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress } = await loadFixture(deployCoreProtocolFixture);

  const [ , , , , projectOwner ] = await ethers.getSigners();

  // get current block timestamp
  const block = await ethers.provider.getBlock("latest");

  const tbankPriceInEth = ethers.utils.parseEther("0.000022");
  const minTbankAmount = ethers.utils.parseEther("100");
  const maxTbankAmount = ethers.utils.parseEther("10000");
  const presaleStart = block.timestamp + 1000;
  const presaleEnd = presaleStart + 604800; // 7 days
  const relaseDelay = 172800; // 2 days
  const vestingPeriod = 864000; // 10 days

  await launchpadFactory.connect(projectOwner).createLaunchpad(
    "TBNK Seed Round",
    token.address,
    tbankPriceInEth,
    minTbankAmount,
    maxTbankAmount,
    presaleStart,
    presaleEnd,
    relaseDelay,
    vestingPeriod,
  );

  const launchpadAddress = await launchpadFactory.launchpadAtIndex(0);

  const launchpad = await ethers.getContractAt("Launchpad", launchpadAddress);

  return { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner };

}

describe("TaoPad Launch Pad", function () {

  describe("Deployment", function () {
    it("Should deploy core protocol contracts", async function () {

        const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress } = await loadFixture(deployCoreProtocolFixture);
      
        expect(await token.balanceOf(tokenOwner.address)).to.gt(0);
        expect(launchpadFactory.address).to.not.equal(ethers.constants.AddressZero);

    });
  });

  describe("Core Protocol Logic", function () {
    it("Should create a new project presale", async function () {

      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();
      
      expect(await launchpad.operator()).to.equal(projectOwner.address);
      expect(await launchpad.token()).to.equal(token.address);
      expect(await launchpad.protocolFeeAddress()).to.equal(protocolFeeAddress.address);
      
      expect(await launchpadFactory.launchpadAtIndex(0)).to.equal(launchpad.address);
      expect(await launchpadFactory.launchpadsLength()).to.equal(1);


    });

    it("Should add tokens to presale", async function () {


      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token.connect(tokenOwner).transfer(projectOwner.address, amountToSell);
      await token.connect(projectOwner).approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const protocolFee = await launchpadFactory.protocolFee();
      const netAmount = amountToSell.sub(amountToSell.mul(protocolFee).div(10000));

      expect(await launchpad.tokenHardCap()).to.equal(netAmount);
      
    });

    it("Users should bid for tokens in presale", async function () {

      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();

      const [ , , , , user1 ] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token.connect(tokenOwner).transfer(projectOwner.address, amountToSell);
      await token.connect(projectOwner).approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      console.log(`\t[+] ${ethers.utils.formatEther(ethToToken)} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`);
      console.log(`\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`);

      expect(launchpad.connect(user1).buyTokens({ value: ethAmount })).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      console.log(`\t[+] Current block timestamp: ${block.timestamp}`);
      console.log(`\t[+] Presale start timestamp: ${await launchpad.startDate()}`);

      await launchpad.connect(user1).buyTokens({ value: ethAmount })
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(ethToToken);

    });

    it("Users should can't bid more than max and less than min amount", async function () {

      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();

      const [ , , , , user1 ] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token.connect(tokenOwner).transfer(projectOwner.address, amountToSell);
      await token.connect(projectOwner).approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      console.log(`\t[+] ${ethers.utils.formatEther(ethToToken)} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`);
      console.log(`\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`);

      expect(launchpad.connect(user1).buyTokens({ value: ethAmount })).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      console.log(`\t[+] Current block timestamp: ${block.timestamp}`);
      console.log(`\t[+] Presale start timestamp: ${await launchpad.startDate()}`);

      await launchpad.connect(user1).buyTokens({ value: ethAmount })
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(ethToToken);

    });

    it("Should distribute allocation for TPAD holders", async function () {

      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token.connect(tokenOwner).transfer(projectOwner.address, amountToSell);
      await token.connect(projectOwner).approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const protocolFee = await launchpadFactory.protocolFee();
      const feeAmount = amountToSell.mul(protocolFee).div(10000);

      expect(await token.balanceOf(protocolFeeAddress.address)).to.equal(feeAmount);

    });

    it("Users should claim tokens after presale end", async function () {

      const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress, launchpad, projectOwner } = await deployLaunchpad();

      const [ , , , , user1 ] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token.connect(tokenOwner).transfer(projectOwner.address, amountToSell);
      await token.connect(projectOwner).approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      console.log(`\t[+] ${ethers.utils.formatEther(ethToToken)} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`);
      console.log(`\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`);

      expect(launchpad.connect(user1).buyTokens({ value: ethAmount })).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      console.log(`\t[+] Current block timestamp: ${block.timestamp}`);
      console.log(`\t[+] Presale start timestamp: ${await launchpad.startDate()}`);

      await launchpad.connect(user1).buyTokens({ value: ethAmount })
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(ethToToken);

      await time.setNextBlockTimestamp(await launchpad.endDate());

      expect(await launchpad.isClaimable()).to.be.false;

      const endDateAfterRelease = (await launchpad.endDate()).add(await launchpad.releaseDelay());

      await time.setNextBlockTimestamp(endDateAfterRelease.add(86400)); // 1 day after release delay
      await mine();

      const newBlock = await ethers.provider.getBlock("latest");

      console.log(`\t[+] Current block timestamp: ${newBlock.timestamp}`);
      console.log(`\t[+] Presale+delay end timestamp: ${endDateAfterRelease}`);

      expect(await launchpad.isClaimable()).to.be.true;

      const user1BalanceBeforeClaim = await token.balanceOf(user1.address);
      await launchpad.connect(user1).claimTokens();
      const user1BalanceAfterClaim = await token.balanceOf(user1.address);
      const netBalance = user1BalanceAfterClaim.sub(user1BalanceBeforeClaim);

      console.log(`\t[+] User 1 claimed: ${ethers.utils.formatEther(netBalance)}`);

      const newClaimableAmount = await launchpad.claimableAmount(user1.address);

      expect(newClaimableAmount).to.equal(0);

      console.log(`\t[+] User 1 claimable amount after first claim: ${ethers.utils.formatEther(newClaimableAmount)}`);

      const vestingDuration = await launchpad.vestingDuration();

      await time.setNextBlockTimestamp(newBlock.timestamp + vestingDuration.toNumber());
      await mine();

      console.log("\t[+] Vesting duration passed");

      const newClaimableAmountAfterVesting = await launchpad.claimableAmount(user1.address);

      const amountToClaim = (await launchpad.purchasedAmount(user1.address)).sub(await launchpad.claimedAmount(user1.address));

      expect(newClaimableAmountAfterVesting).to.equal(amountToClaim);

      console.log(`\t[+] User 1 claimable amount after vesting: ${ethers.utils.formatEther(newClaimableAmountAfterVesting)}`);

      const user1BalanceBeforeClaim2 = await token.balanceOf(user1.address);
      await launchpad.connect(user1).claimTokens();
      const user1BalanceAfterClaim2 = await token.balanceOf(user1.address);

      const netBalance2 = user1BalanceAfterClaim2.sub(user1BalanceBeforeClaim2);

      expect(netBalance2).to.equal(amountToClaim);

      console.log(`\t[+] User 1 claimed: ${ethers.utils.formatEther(netBalance2)}`);

      console.log(`\t[+] Withdraw unsold tokens`);

      const operator = projectOwner;

      const operatorBalanceBefore = await token.balanceOf(operator.address);

      await launchpad.connect(operator).withdrawTokens();

      const operatorBalanceAfter = await token.balanceOf(operator.address);

      const newOperatorBalance = operatorBalanceAfter.sub(operatorBalanceBefore);

      console.log(`\t[+] Operator balance after withdraw unsold tokens: ${ethers.utils.formatEther(newOperatorBalance)}`);

      console.log(`\t[+] Withdraw gained ETH`);

      const projectOwnerBalanceBefore = await ethers.provider.getBalance(operator.address);

      await launchpad.connect(operator).withdrawEth();

      const projectOwnerBalanceAfter = await ethers.provider.getBalance(operator.address);

      const newProjectOwnerBalance = projectOwnerBalanceAfter.sub(projectOwnerBalanceBefore);

      console.log(`\t[+] Project owner balance after withdraw ETH: ${ethers.utils.formatEther(newProjectOwnerBalance)}`);

    });

  });

});