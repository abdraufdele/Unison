"""Regression check for keystore submission during a simulation."""

from unittest.mock import Mock, patch
from web3 import IPCProvider, Web3
from hexbytes import HexBytes
from web3.datastructures import AttributeDict

from deployment import sendOperation
from environment import OperatorRpc


# Exercise the signed branch with a simulated receipt and inspect the subprocess environment before dispatch.
def checkSimulatedSigner():
    socket = "/tmp/unison-routing-regression.ipc"
    w = Mock()
    w.provider = IPCProvider(socket)
    w.eth.chain_id = 1301
    actor = Web3.to_checksum_address("0x" + "11" * 20)
    fn = Mock(spec=["data_in_transaction"])
    fn.data_in_transaction = "0x1234"
    w.eth.get_transaction_count.return_value = 7
    w.eth.wait_for_transaction_receipt.return_value = AttributeDict(
        {"status": 1, "transactionHash": HexBytes("0xaa")}
    )
    w.eth.get_transaction.return_value = AttributeDict(
        {"from": actor, "nonce": 7, "input": HexBytes("0x1234"), "to": None}
    )
    public = "https://sepolia.unichain.org"
    with patch("deployment.subprocess.check_output", return_value="0xaa") as cast:
        sendOperation(w, {"rpc": public, "chainId": 1301}, fn, actor, "example")
        assert cast.call_args.kwargs["env"]["ETH_RPC_URL"] == socket
        assert public not in cast.call_args.args[0]
    print("Simulated keystore route uses only the owned IPC endpoint.")


# Confirm that even an HTTP transport failure containing the full URL yields only the method and error type.
def checkTransportError():
    url = "https://rpc.invalid/private-example"
    provider = OperatorRpc(url)
    with patch.object(Web3.HTTPProvider, "make_request", side_effect=ConnectionError(url)):
        try:
            provider.make_request("eth_chainId", [])
        except ConnectionError as exc:
            assert "eth_chainId" in str(exc) and url not in str(exc) and exc.__suppress_context__
        else:
            raise AssertionError("transport error was lost")
    print("RPC transport errors omit endpoint credentials.")


if __name__ == "__main__":
    checkSimulatedSigner()
    checkTransportError()
