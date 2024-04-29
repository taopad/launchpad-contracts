import {
  time,
  loadFixture,
  mine,
} from "@nomicfoundation/hardhat-network-helpers";
import { anyValue } from "@nomicfoundation/hardhat-chai-matchers/withArgs";
import { expect } from "chai";
import { ethers } from "hardhat";
import {
  LaunchpadDeployer__factory,
  LaunchpadFactory__factory,
  TokenMockup__factory,
  LaunchpadV2__factory,
  LaunchpadFactory,
  LaunchpadV2,
  TokenMockup,
} from "../typechain-types";
import keccak256 from "keccak256";
import MerkleTree from "merkletreejs";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";

interface LaunchpadTestContext {
  token: TokenMockup;
  tokenOwner: SignerWithAddress;
  launchpadFactory: LaunchpadFactory;
  deployer: SignerWithAddress;
  protocolFeeAddress: SignerWithAddress;
  launchpadV2: LaunchpadV2; 
  users: SignerWithAddress[];
  proofs: string[][];
}


function consoleLog(...args: any[]) {
  //console.log(...args);
}

function createWhitelist(users: any[]) {
  const leaves = users.map(addr => keccak256(addr));
  const tree = new MerkleTree(leaves, keccak256, { sortPairs: true });
  const root = tree.getRoot().toString('hex');
  const proofs = users.map(addr => tree.getHexProof(keccak256(addr)));

  return { tree, root, proofs };
}

async function deployTokenFixture() {
  const [tokenOwner] = await ethers.getSigners();

  const token = await new TokenMockup__factory(tokenOwner).deploy();
  await token.deployed();

  return { token, tokenOwner };
}

async function deployLaunchpadFixture() {
  const [, deployer, protocolFeeAddress] = await ethers.getSigners();

  const launchpadDeployer = await new LaunchpadDeployer__factory(deployer).deploy();
  const launchpadFactory = await new LaunchpadFactory__factory(deployer).deploy(
    protocolFeeAddress.address,
    100,
    launchpadDeployer.address
  );
  await launchpadFactory.deployed();

  return { launchpadFactory, deployer, protocolFeeAddress };
}

async function deployLaunchpadV2Fixture() {
  const [deployer, protocolFeeAddress, ...users] = await ethers.getSigners();

  const token = await new TokenMockup__factory(deployer).deploy();
  await token.deployed();

  const launchpadDeployer = await new LaunchpadDeployer__factory(deployer).deploy();
  const launchpadFactory = await new LaunchpadFactory__factory(deployer).deploy(
    protocolFeeAddress.address,
    100,
    launchpadDeployer.address
  );
  await launchpadFactory.deployed();

  const { root, proofs } = createWhitelist(users.map(u => u.address));

  // Get the current block timestamp
  const currentBlock = await ethers.provider.getBlock('latest');
  const startDate = currentBlock.timestamp + 1000;  // Calculate start date
  const endDate = startDate + 604800;  // Calculate end date

  const launchpadInfo = {
    name: "TBNK Seed Round",
    token: token.address,
    ethPricePerToken: ethers.utils.parseEther("0.000022"),
    minTokenBuy: ethers.utils.parseEther("100"),
    maxTokenBuy: ethers.utils.parseEther("10000"),
    startDate: startDate,
    endDate: endDate,
    releaseDelay: 172800, // 2 days
    vestingDuration: 864000, // 10 days
    root: root  // Root of the Merkle tree for whitelisting
  };

  await launchpadFactory.connect(deployer).createLaunchpad(launchpadInfo);
  const launchpadAddress = await launchpadFactory.launchpadAtIndex(0);
  const launchpadV2 = LaunchpadV2__factory.connect(launchpadAddress, deployer);

  return {
    token,
    tokenOwner: deployer,
    launchpadFactory,
    deployer,
    protocolFeeAddress,
    launchpadV2,
    users,
    proofs
  };
}

async function deployCoreProtocolFixture() {
  const { token, tokenOwner } = await loadFixture(deployTokenFixture);
  const { launchpadFactory, deployer, protocolFeeAddress } = await loadFixture(
    deployLaunchpadFixture
  );

  return { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress };
}

async function deployLaunchpad() {
  const { token, tokenOwner, launchpadFactory, deployer, protocolFeeAddress } =
    await loadFixture(deployCoreProtocolFixture);

  const [, , , , projectOwner] = await ethers.getSigners();

  // get current block timestamp
  const block = await ethers.provider.getBlock("latest");

  const tbankPriceInEth = ethers.utils.parseEther("0.000022");
  const minTbankAmount = ethers.utils.parseEther("100");
  const maxTbankAmount = ethers.utils.parseEther("10000");
  const presaleStart = block.timestamp + 1000;
  const presaleEnd = presaleStart + 604800; // 7 days
  const relaseDelay = 172800; // 2 days
  const vestingPeriod = 864000; // 10 days

  await launchpadFactory.connect(projectOwner).createLaunchpad({
    name: "TBNK Seed Round",
    token: token.address,
    ethPricePerToken: tbankPriceInEth,
    minTokenBuy: minTbankAmount,
    maxTokenBuy: maxTbankAmount,
    startDate: presaleStart,
    endDate: presaleEnd,
    releaseDelay: relaseDelay,
    vestingDuration: vestingPeriod,
  });

  const launchpadAddress = await launchpadFactory.launchpadAtIndex(0);

  const launchpad = await ethers.getContractAt("Launchpad", launchpadAddress);

  return {
    token,
    tokenOwner,
    launchpadFactory,
    deployer,
    protocolFeeAddress,
    launchpad,
    projectOwner,
  };
}

describe("TaoPad Launch Pad", function () {
  describe("Deployment", function () {
    it("Should deploy core protocol contracts", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
      } = await loadFixture(deployCoreProtocolFixture);

      expect(await token.balanceOf(tokenOwner.address)).to.gt(0);
      expect(launchpadFactory.address).to.not.equal(
        ethers.constants.AddressZero
      );
    });
  });

    
  describe("Whitelist and Merkle Proof Verification", function () {
    let fixtures: LaunchpadTestContext;  
  
    before(async () => {
      fixtures = await loadFixture(deployLaunchpadV2Fixture);
    });
  
    it("should allow a whitelisted user to participate in the presale with valid proof", async function () {
      const { launchpadV2, users, proofs } = fixtures;  
      const user1 = users[0];
      const proof = proofs[0];
      const maxTokenAmount = ethers.utils.parseEther("500");
  
      await expect(launchpadV2.connect(user1).buyTokens(user1.address, maxTokenAmount, proof, { value: ethers.utils.parseEther("1") }))
        .to.emit(launchpadV2, 'TokensPurchased')
        .withArgs(user1.address, ethers.utils.parseEther("1"), anyValue);  // TODO: Adjust `anyValue` as necessary
    });
  
    it("should reject a user trying to participate without valid proof", async function () {
      const { launchpadV2, users } = fixtures;
      const user2 = users[1];
      const invalidProof: string[] = [];  
      const maxTokenAmount = ethers.utils.parseEther("500");
  
      await expect(launchpadV2.connect(user2).buyTokens(user2.address, maxTokenAmount, invalidProof, { value: ethers.utils.parseEther("1") }))
        .to.be.revertedWith("InvalidProof");
    });
  });
  
  describe("Core Protocol Logic", function () {
    it("Should create a new project presale", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      expect(await launchpad.operator()).to.equal(projectOwner.address);
      expect(await launchpad.token()).to.equal(token.address);
      expect(await launchpad.protocolFeeAddress()).to.equal(
        protocolFeeAddress.address
      );

      expect(await launchpadFactory.launchpadAtIndex(0)).to.equal(
        launchpad.address
      );
      expect(await launchpadFactory.launchpadsLength()).to.equal(1);
    });

    it("Should add tokens to presale", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token
        .connect(tokenOwner)
        .transfer(projectOwner.address, amountToSell);
      await token
        .connect(projectOwner)
        .approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const protocolFee = await launchpadFactory.protocolFee();
      const netAmount = amountToSell.sub(
        amountToSell.mul(protocolFee).div(10000)
      );

      expect(await launchpad.tokenHardCap()).to.equal(netAmount);
    });

    it("Users should bid for tokens in presale", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      const [, , , , user1] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token
        .connect(tokenOwner)
        .transfer(projectOwner.address, amountToSell);
      await token
        .connect(projectOwner)
        .approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      consoleLog(
        `\t[+] ${ethers.utils.formatEther(
          ethToToken
        )} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`
      );
      consoleLog(
        `\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`
      );

      expect(
        launchpad.connect(user1).buyTokens([], { value: ethAmount })
      ).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      consoleLog(`\t[+] Current block timestamp: ${block.timestamp}`);
      consoleLog(
        `\t[+] Presale start timestamp: ${await launchpad.startDate()}`
      );

      await launchpad.connect(user1).buyTokens([], { value: ethAmount });
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(
        ethToToken
      );
    });

    it("Users should can't bid more than max and less than min amount", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      const [, , , , user1] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token
        .connect(tokenOwner)
        .transfer(projectOwner.address, amountToSell);
      await token
        .connect(projectOwner)
        .approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      consoleLog(
        `\t[+] ${ethers.utils.formatEther(
          ethToToken
        )} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`
      );
      consoleLog(
        `\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`
      );

      expect(
        launchpad.connect(user1).buyTokens([], { value: ethAmount })
      ).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      consoleLog(`\t[+] Current block timestamp: ${block.timestamp}`);
      consoleLog(
        `\t[+] Presale start timestamp: ${await launchpad.startDate()}`
      );

      await launchpad.connect(user1).buyTokens([], { value: ethAmount });
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(
        ethToToken
      );
    });

    it("Should distribute allocation for TPAD holders", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token
        .connect(tokenOwner)
        .transfer(projectOwner.address, amountToSell);
      await token
        .connect(projectOwner)
        .approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const protocolFee = await launchpadFactory.protocolFee();
      const feeAmount = amountToSell.mul(protocolFee).div(10000);

      expect(await token.balanceOf(protocolFeeAddress.address)).to.equal(
        feeAmount
      );
    });

    it("Users should claim tokens after presale end", async function () {
      const {
        token,
        tokenOwner,
        launchpadFactory,
        deployer,
        protocolFeeAddress,
        launchpad,
        projectOwner,
      } = await deployLaunchpad();

      const [, , , , user1] = await ethers.getSigners();

      const amountToSell = ethers.utils.parseEther("1000000");
      await token
        .connect(tokenOwner)
        .transfer(projectOwner.address, amountToSell);
      await token
        .connect(projectOwner)
        .approve(launchpad.address, amountToSell);

      await launchpad.connect(projectOwner).increaseHardCap(amountToSell);

      const ethAmount = ethers.utils.parseEther("0.1");
      const ethPricePerToken = await launchpad.ethPricePerToken();
      const ethToToken = await launchpad.ethToToken(ethAmount);

      consoleLog(
        `\t[+] ${ethers.utils.formatEther(
          ethToToken
        )} tokens for ${ethers.utils.formatEther(ethAmount)} ETH`
      );
      consoleLog(
        `\t[+] ${ethers.utils.formatEther(ethPricePerToken)} ETH per token`
      );

      expect(
        launchpad.connect(user1).buyTokens([], { value: ethAmount })
      ).to.be.revertedWith("Launchpad: NOT_STARTED");

      await time.setNextBlockTimestamp(await launchpad.startDate());

      const block = await ethers.provider.getBlock("latest");

      consoleLog(`\t[+] Current block timestamp: ${block.timestamp}`);
      consoleLog(
        `\t[+] Presale start timestamp: ${await launchpad.startDate()}`
      );

      await launchpad.connect(user1).buyTokens([], { value: ethAmount });
      expect(await launchpad.purchasedAmount(user1.address)).to.equal(
        ethToToken
      );

      await time.setNextBlockTimestamp(await launchpad.endDate());

      expect(await launchpad.isClaimable()).to.be.false;

      const endDateAfterRelease = (await launchpad.endDate()).add(
        await launchpad.releaseDelay()
      );

      await time.setNextBlockTimestamp(endDateAfterRelease.add(86400)); // 1 day after release delay
      await mine();

      const newBlock = await ethers.provider.getBlock("latest");

      consoleLog(`\t[+] Current block timestamp: ${newBlock.timestamp}`);
      consoleLog(`\t[+] Presale+delay end timestamp: ${endDateAfterRelease}`);

      expect(await launchpad.isClaimable()).to.be.true;

      const user1BalanceBeforeClaim = await token.balanceOf(user1.address);
      await launchpad.connect(user1).claimTokens();
      const user1BalanceAfterClaim = await token.balanceOf(user1.address);
      const netBalance = user1BalanceAfterClaim.sub(user1BalanceBeforeClaim);

      consoleLog(
        `\t[+] User 1 claimed: ${ethers.utils.formatEther(netBalance)}`
      );

      const newClaimableAmount = await launchpad.claimableAmount(user1.address);

      expect(newClaimableAmount).to.equal(0);

      consoleLog(
        `\t[+] User 1 claimable amount after first claim: ${ethers.utils.formatEther(
          newClaimableAmount
        )}`
      );

      const vestingDuration = await launchpad.vestingDuration();

      await time.setNextBlockTimestamp(
        newBlock.timestamp + vestingDuration.toNumber()
      );
      await mine();

      consoleLog("\t[+] Vesting duration passed");

      const newClaimableAmountAfterVesting = await launchpad.claimableAmount(
        user1.address
      );

      const amountToClaim = (
        await launchpad.purchasedAmount(user1.address)
      ).sub(await launchpad.claimedAmount(user1.address));

      expect(newClaimableAmountAfterVesting).to.equal(amountToClaim);

      consoleLog(
        `\t[+] User 1 claimable amount after vesting: ${ethers.utils.formatEther(
          newClaimableAmountAfterVesting
        )}`
      );

      const user1BalanceBeforeClaim2 = await token.balanceOf(user1.address);
      await launchpad.connect(user1).claimTokens();
      const user1BalanceAfterClaim2 = await token.balanceOf(user1.address);

      const netBalance2 = user1BalanceAfterClaim2.sub(user1BalanceBeforeClaim2);

      expect(netBalance2).to.equal(amountToClaim);

      consoleLog(
        `\t[+] User 1 claimed: ${ethers.utils.formatEther(netBalance2)}`
      );

      consoleLog(`\t[+] Withdraw unsold tokens`);

      const operator = projectOwner;

      const operatorBalanceBefore = await token.balanceOf(operator.address);

      await launchpad.connect(operator).withdrawTokens();

      const operatorBalanceAfter = await token.balanceOf(operator.address);

      const newOperatorBalance = operatorBalanceAfter.sub(
        operatorBalanceBefore
      );

      consoleLog(
        `\t[+] Operator balance after withdraw unsold tokens: ${ethers.utils.formatEther(
          newOperatorBalance
        )}`
      );

      consoleLog(`\t[+] Withdraw gained ETH`);

      const projectOwnerBalanceBefore = await ethers.provider.getBalance(
        operator.address
      );

      await launchpad.connect(operator).withdrawEth();

      const projectOwnerBalanceAfter = await ethers.provider.getBalance(
        operator.address
      );

      const newProjectOwnerBalance = projectOwnerBalanceAfter.sub(
        projectOwnerBalanceBefore
      );

      consoleLog(
        `\t[+] Project owner balance after withdraw ETH: ${ethers.utils.formatEther(
          newProjectOwnerBalance
        )}`
      );
    });
  });
});
