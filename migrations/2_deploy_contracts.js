var Casino = artifacts.require("./Casino.sol");
var Dealer = artifacts.require("./Dealer.sol");

module.exports = function(deployer) {
  deployer.deploy(Dealer);
  deployer.deploy(Casino);
};
