import React, { Component } from 'react'
import CasinoContract from '../build/contracts/Casino.json'
import getWeb3 from './utils/getWeb3'

import './css/oswald.css'
import './css/open-sans.css'
import './css/pure-min.css'
import './App.css'

class App extends Component {
  constructor(props) {
    super(props);

    this.state = {
      storageValue: 0
    };
  }

  componentWillMount() {
    // Get network provider and web3 instance.
    // See utils/getWeb3 for more info.

    getWeb3
    .then(results => {
      this.setState({
        web3: results.web3
      });

      // Instantiate contract once web3 provided.
      this.instantiateContract();
    });
  }

  instantiateContract() {
    const contract = require('truffle-contract');
    const casino = contract(CasinoContract);
    casino.setProvider(this.state.web3.currentProvider);

    var _casino; // the instance

    // Get accounts.
    this.state.web3.eth.getAccounts((error, accounts) => {
      casino.deployed().then((instance) => {
        _casino = instance;
        this.state.web3.eth.defaultAccount = accounts[0];
        _casino.joinGame.call({
          'from': accounts[0]
        });
      }).then((result) => {
        // And chain them
      });
    });
  }

  render() {
    return (
      <div className="App">
        <nav className="navbar pure-menu pure-menu-horizontal">
            <a href="#" className="pure-menu-heading pure-menu-link">Truffle Box</a>
        </nav>

        <main className="container">
          <div className="pure-g">
            <div className="pure-u-1-1">
              <h1>Good to Go!</h1>
              <p>Your Truffle Box is installed and ready.</p>
              <h2>Smart Contract Example</h2>
              <p>If your contracts compiled and migrated successfully, below will show a stored value of 5 (by default).</p>
              <p>Try changing the value stored on <strong>line 59</strong> of App.js.</p>
              <p>The stored value is: {this.state.storageValue}</p>
            </div>
          </div>
        </main>
      </div>
    );
  }
}

export default App
