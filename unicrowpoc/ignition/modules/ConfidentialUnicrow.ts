import { buildModule } from "@nomicfoundation/hardhat-ignition/modules";

export default buildModule("ConfidentialUnicrow", (m) => {
  // Deploy ConfidentialERC20 token first
  const confidentialToken = m.contract("ConfidentialERC20", []);

  // Deploy ConfidentialUnicrow with the token address
  const confidentialUnicrow = m.contract("ConfidentialUnicrow", [
    confidentialToken,
  ]);

  return { confidentialToken, confidentialUnicrow };
});
