import { expect } from "chai";
import { namedWallets, wallet, publicClient } from "../utils/wallet";
import { WalletClient } from "viem";

// Type guard for wallet account
function hasAccount(wallet: WalletClient): wallet is WalletClient & { account: { address: Address } } {
  return wallet.account !== undefined && wallet.account !== null;
}
import {
  Address,
  getContract,
  parseEther,
  formatEther,
  getAddress,
  parseAbiItem,
} from "viem";
import contractAbi from "../artifacts/contracts/ConfidentialUnicrow/ConfidentialUnicrow.sol/ConfidentialUnicrow.json";
import tokenAbi from "../artifacts/contracts/ConfidentialERC20.sol/ConfidentialERC20.json";
import { HexString } from "@inco/js/dist/binary";
// @ts-ignore
import { Lightning } from "@inco/js/lite";

interface Escrow {
  buyer: Address;
  seller: Address;
  arbitrator: Address;
  amount: HexString;
  challengePeriod: bigint;
  createdAt: bigint;
  isDisputed: boolean;
  isResolved: boolean;
  isClaimed: boolean;
  isCancelled: boolean;
}

describe("ConfidentialUnicrow Escrow Tests", function () {


  // Helper function to wait between transactions
  const waitForTransaction = async (txHash: `0x${string}`) => {
    await publicClient.waitForTransactionReceipt({ hash: txHash });
    // Add longer delay to ensure nonce is updated
    await new Promise(resolve => setTimeout(resolve, 5000));
  };

  // Common ABI definitions
  const approveFunctionAbi = tokenAbi.abi.find(
    (item) =>
      item.name === "approve" &&
      item.inputs.length === 2 &&
      item.inputs[1].type === "bytes"
  );
  
  const payFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "pay" &&
      item.inputs.length === 1 &&
      item.inputs[0].type === "tuple"
  );
  

  const releaseFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "release" &&
      item.inputs.length === 1 &&
      item.inputs[0].type === "uint256"
  );

  const disputeFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "dispute" &&
      item.inputs.length === 1 &&
      item.inputs[0].type === "uint256"
  );

  const resolveFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "resolve" &&
      item.inputs.length === 3 &&
      item.inputs[0].type === "uint256" &&
      item.inputs[1].type === "bytes" &&
      item.inputs[2].type === "bytes"
  );

  const claimFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "claim" &&
      item.inputs.length === 1 &&
      item.inputs[0].type === "uint256"
  );

  const cancelFunctionAbi = contractAbi.abi.find(
    (item) =>
      item.name === "cancel" &&
      item.inputs.length === 1 &&
      item.inputs[0].type === "uint256"
  );

  // Helper function to get next nonce
  const getNextNonce = async () => {
    return await publicClient.getTransactionCount({
      address: wallet.account.address,
    });
  };
  let confidentialUnicrow: any;
  let confidentialToken: any;
  let unicrowAddress: Address;
  let tokenAddress: Address;
  let incoConfig: any;
  let reEncryptorForMainWallet: any;
  let reEncryptorForAliceWallet: any;
  let reEncryptorForBobWallet: any;
  let reEncryptorForArbitratorWallet: any;

  // Deploy contracts once before all tests
  before(async function () {
    const chainId = publicClient.chain.id;
    console.log("Running on chain:", chainId);

    if (chainId === 31337) {
      incoConfig = Lightning.localNode();
    } else {
      incoConfig = Lightning.latest("testnet", 84532);
    }

    reEncryptorForMainWallet = await incoConfig.getReencryptor(wallet);
    reEncryptorForAliceWallet = await incoConfig.getReencryptor(
      namedWallets.alice,
    );
    reEncryptorForBobWallet = await incoConfig.getReencryptor(namedWallets.bob);
    reEncryptorForArbitratorWallet = await incoConfig.getReencryptor(
      namedWallets.carol,
    ); // Using carol as arbitrator

    // Deploy ConfidentialERC20 token first
    const tokenTxHash = await wallet.deployContract({
      abi: tokenAbi.abi,
      bytecode: tokenAbi.bytecode as HexString,
      args: [],
    });

    const tokenReceipt = await publicClient.waitForTransactionReceipt({
      hash: tokenTxHash,
    });
    tokenAddress = tokenReceipt.contractAddress as Address;
    console.log(`ConfidentialERC20 deployed at: ${tokenAddress}`);

    const unicrowTxHash = await wallet.deployContract({
      abi: contractAbi.abi,
      bytecode: contractAbi.bytecode as HexString,
      args: [tokenAddress],
    });

    const unicrowReceipt = await publicClient.waitForTransactionReceipt({
      hash: unicrowTxHash,
    });
    unicrowAddress = unicrowReceipt.contractAddress as Address;
    console.log(`ConfidentialUnicrow deployed at: ${unicrowAddress}`);

    for (const [name, userWallet] of Object.entries(namedWallets)) {
      if (!hasAccount(userWallet)) continue;
      
      const balance = await publicClient.getBalance({
        address: userWallet.account.address,
      });
      const balanceEth = Number(formatEther(balance));

      if (balanceEth < 0.001) {
        const neededEth = 0.001 - balanceEth;
        const tx = await wallet.sendTransaction({
          to: userWallet.account.address,
          value: parseEther(neededEth.toFixed(6)),
        });
        await publicClient.waitForTransactionReceipt({ hash: tx });
        console.log(`${name} funded: ${userWallet.account.address}`);
      }
    }

  });

  // Reset contract state before each test
  beforeEach(async function () {
    // Deploy new ConfidentialUnicrow contract to reset state
    const unicrowTxHash = await wallet.deployContract({
      abi: contractAbi.abi,
      bytecode: contractAbi.bytecode as HexString,
      args: [tokenAddress],
    });

    const unicrowReceipt = await publicClient.waitForTransactionReceipt({
      hash: unicrowTxHash,
    });
    unicrowAddress = unicrowReceipt.contractAddress as Address;
    console.log(`Deployed ConfidentialUnicrow at: ${unicrowAddress}`);

    const mintAmount = parseEther("10000");
    const mintFunctionAbi = tokenAbi.abi.find(
      (item) =>
        item.name === "mint" &&
        item.inputs.length === 1
    );

    const mintTx = await wallet.writeContract({
      address: tokenAddress,
      abi: [mintFunctionAbi],
      functionName: "mint",
      args: [mintAmount],
    });

    await waitForTransaction(mintTx);
    console.log(`Minted ${formatEther(mintAmount)} tokens for testing`);
  });

  describe("Escrow Creation and Basic Flow", function () {
    it("Should create an escrow with encrypted amount", async function () {
      const escrowAmount = parseEther("1000");
      const challengePeriod = 3600; // 1 hour

      // Encrypt the escrow amount
      const encryptedAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: unicrowAddress,
      });

            // Approve tokens for the escrow contract


      const encryptedApproveAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: tokenAddress
      });

      const nonce = await getNextNonce();
      const approveTx = await wallet.writeContract({
        address: tokenAddress,
        abi: [approveFunctionAbi],
        functionName: "approve",
        args: [
          unicrowAddress,
          encryptedApproveAmount
        ],
        nonce
      });
      
      await waitForTransaction(approveTx);
      console.log("Token approval successful");

      // Create escrow
      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      const escrowInput = {
        seller: namedWallets.alice.account.address,
        arbitrator: namedWallets.carol.account.address,
        encryptedAmount: encryptedAmount,
        challengePeriod: challengePeriod,
      };

      const payNonce = await getNextNonce();
      const txHash = await wallet.writeContract({
        address: unicrowAddress,
        abi: [payFunctionAbi],
        functionName: "pay",
        args: [escrowInput],
        nonce: payNonce
      });
      
      await waitForTransaction(txHash);
      console.log("Escrow created successfully");

      // Get escrow details
      const escrowId = 0; // First escrow
      const escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;

      expect(escrow.buyer).to.equal(wallet.account.address);
      expect(escrow.seller).to.equal(namedWallets.alice.account.address);
      expect(escrow.arbitrator).to.equal(namedWallets.carol.account.address);
      expect(Number(escrow.challengePeriod)).to.equal(challengePeriod);
      expect(escrow.isDisputed).to.be.false;
      expect(escrow.isResolved).to.be.false;
      expect(escrow.isClaimed).to.be.false;
      expect(escrow.isCancelled).to.be.false;
    });

    it("Should allow buyer to release payment to seller", async function () {
      const escrowAmount = parseEther("500");
      const challengePeriod = 3600;

      // Create escrow
      const encryptedAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: unicrowAddress,
      });




      const encryptedApproveAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: tokenAddress
      });

      const approveNonce = await getNextNonce();
      const approveTx = await wallet.writeContract({
        address: tokenAddress,
        abi: [approveFunctionAbi],
        functionName: "approve",
        args: [
          unicrowAddress,
          encryptedApproveAmount
        ],
        nonce: approveNonce
      });
      await waitForTransaction(approveTx);

      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      const escrowInput = {
        seller: namedWallets.alice.account.address,
        arbitrator: namedWallets.carol.account.address,
        encryptedAmount: encryptedAmount,
        challengePeriod: challengePeriod,
      };



      const payNonce = await getNextNonce();
      await wallet.writeContract({
        address: unicrowAddress,
        abi: [payFunctionAbi],
        functionName: "pay",
        args: [escrowInput],
        nonce: payNonce
      });
      console.log("Escrow created for release test");

      // Release payment
      const escrowId = 0;
      const releaseFunctionAbi = contractAbi.abi.find(
        (item) =>
          item.name === "release" &&
          item.inputs.length === 1 &&
          item.inputs[0].type === "uint256"
      );

      const releaseTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: [releaseFunctionAbi],
        functionName: "release",
        args: [escrowId],
      });
      
      await publicClient.waitForTransactionReceipt({ hash: releaseTx });
      console.log("Payment released to seller");

      // Check escrow status
      const escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;
      expect(escrow.isClaimed).to.be.true;
    });
  });

  describe("Dispute Resolution", function () {
    it("Should allow buyer to initiate dispute and arbitrator to resolve", async function () {
      const escrowAmount = parseEther("2000");
      const challengePeriod = 3600;

      // Create escrow
      const encryptedAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: unicrowAddress,
      });

      const encryptedApproveAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: tokenAddress
      });

      const approveNonce = await getNextNonce();
      const approveTx = await wallet.writeContract({
        address: tokenAddress,
        abi: [approveFunctionAbi],
        functionName: "approve",
        args: [
          unicrowAddress,
          encryptedApproveAmount
        ],
        nonce: approveNonce
      });
      await waitForTransaction(approveTx);

      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      const escrowInput = {
        seller: namedWallets.alice.account.address,
        arbitrator: namedWallets.carol.account.address,
        encryptedAmount: encryptedAmount,
        challengePeriod: challengePeriod,
      };



      const payNonce = await getNextNonce();
      const payTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: [payFunctionAbi],
        functionName: "pay",
        args: [escrowInput],
        nonce: payNonce
      });
      await waitForTransaction(payTx);
      console.log("Escrow created for dispute test");

      const escrowId = 0;

      // Initiate dispute


      const disputeNonce = await getNextNonce();
      const disputeTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: [disputeFunctionAbi],
        functionName: "dispute",
        args: [escrowId],
        nonce: disputeNonce
      });
      
      await waitForTransaction(disputeTx);
      console.log("Dispute initiated");

      // Check dispute status
      let escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;
      expect(escrow.isDisputed).to.be.true;

      // Arbitrator resolves dispute
      const buyerAmount = parseEther("1500"); // Return 1500 to buyer
      const sellerAmount = parseEther("500"); // Give 500 to seller

      const encryptedBuyerAmount = await incoConfig.encrypt(buyerAmount, {
        accountAddress: namedWallets.carol.account.address,
        dappAddress: unicrowAddress,
      });

      const encryptedSellerAmount = await incoConfig.encrypt(sellerAmount, {
        accountAddress: namedWallets.carol.account.address,
        dappAddress: unicrowAddress,
      });

      // Use arbitrator wallet to resolve
      const resolveNonce = await publicClient.getTransactionCount({
        address: namedWallets.carol.account.address,
      });
      const resolveTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "resolve",
        args: [escrowId, encryptedBuyerAmount, encryptedSellerAmount],
        account: namedWallets.carol.account,
        nonce: resolveNonce
      });

      await waitForTransaction(resolveTx);
      console.log("Dispute resolved by arbitrator");

      // Check final status
      escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;
      expect(escrow.isResolved).to.be.true;
      expect(escrow.isClaimed).to.be.true;
    });
  });

  describe("Challenge Period and Claims", function () {
    it("Should allow seller to claim after challenge period", async function () {
      const escrowAmount = parseEther("750");
      const challengePeriod = 1; // Very short for testing

      // Create escrow
      const encryptedAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: unicrowAddress,
      });



      const encryptedApproveAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: tokenAddress
      });

      const approveNonce = await getNextNonce();
      const approveTx = await wallet.writeContract({
        address: tokenAddress,
        abi: [approveFunctionAbi],
        functionName: "approve",
        args: [
          unicrowAddress,
          encryptedApproveAmount
        ],
        nonce: approveNonce
      });
      await waitForTransaction(approveTx);

      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      const escrowInput = {
        seller: namedWallets.alice.account.address,
        arbitrator: namedWallets.carol.account.address,
        encryptedAmount: encryptedAmount,
        challengePeriod: challengePeriod,
      };



      const payNonce = await getNextNonce();
      await wallet.writeContract({
        address: unicrowAddress,
        abi: [payFunctionAbi],
        functionName: "pay",
        args: [escrowInput],
        nonce: payNonce
      });
      console.log("Escrow created with short challenge period");

      const escrowId = 0;

      // Wait for challenge period to end
      console.log("Waiting for challenge period to end...");
      await new Promise((resolve) => setTimeout(resolve, 5000)); // Wait 2 seconds

      // Check if can claim
      const canClaim = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "canClaim",
        args: [escrowId],
      });
      expect(canClaim).to.be.true;

      // Seller claims funds
      const claimNonce = await publicClient.getTransactionCount({
        address: namedWallets.alice.account.address,
      });
      const claimTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "claim",
        args: [escrowId],
        account: namedWallets.alice.account,
        nonce: claimNonce
      });

      await waitForTransaction(claimTx);
      console.log("Seller claimed funds after challenge period");

      // Check final status
      const escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;
      expect(escrow.isClaimed).to.be.true;
    });

    it("Should allow buyer to cancel before challenge period ends", async function () {
      const escrowAmount = parseEther("300");
      const challengePeriod = 3600; // 1 hour

      // Create escrow
      const encryptedAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: unicrowAddress,
      });

      const encryptedApproveAmount = await incoConfig.encrypt(escrowAmount, {
        accountAddress: wallet.account.address,
        dappAddress: tokenAddress
      });

      const approveNonce = await getNextNonce();
      const approveTx = await wallet.writeContract({
        address: tokenAddress,
        abi: [approveFunctionAbi],
        functionName: "approve",
        args: [
          unicrowAddress,
          encryptedApproveAmount
        ],
        nonce: approveNonce
      });
      await waitForTransaction(approveTx);

      if (!hasAccount(namedWallets.alice) || !hasAccount(namedWallets.carol)) {
        throw new Error("Required wallet accounts not available");
      }

      const escrowInput = {
        seller: namedWallets.alice.account.address,
        arbitrator: namedWallets.carol.account.address,
        encryptedAmount: encryptedAmount,
        challengePeriod: challengePeriod,
      };




      const payNonce = await getNextNonce();
      const payTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: [payFunctionAbi],
        functionName: "pay",
        args: [escrowInput],
        nonce: payNonce
      });
      await waitForTransaction(payTx);
      console.log("Escrow created for cancellation test");

      const escrowId = 0;

      // Check if can cancel
      const canCancel = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "canCancel",
        args: [escrowId],
      });
      expect(canCancel).to.be.true;

      // Cancel escrow


      const cancelNonce = await getNextNonce();
      const cancelTx = await wallet.writeContract({
        address: unicrowAddress,
        abi: [cancelFunctionAbi],
        functionName: "cancel",
        args: [escrowId],
        nonce: cancelNonce
      });
      await waitForTransaction(cancelTx);
      console.log("Escrow cancelled by buyer");

      // Check final status
      const escrow = await publicClient.readContract({
        address: unicrowAddress,
        abi: contractAbi.abi,
        functionName: "getEscrow",
        args: [escrowId],
      }) as unknown as Escrow;
      expect(escrow.isCancelled).to.be.true;
    });
  });

  
});
