"""Offline analysis3 runtime regression tests for CVE-2026-115557.

Run with CONDA_ENVIRONMENT=analysis3 python -m pytest scripts/test_analysis3_security.py.
The TLS tests follow CPython's MemoryBIO regression test in python/cpython#160042,
using ephemeral test certificates and no sockets or external TLS services.
"""

from datetime import datetime, timedelta, timezone
import os
import ssl

import pytest

from check_analysis3_security import check_installed

pytestmark = pytest.mark.skipif(
    os.environ.get("CONDA_ENVIRONMENT") != "analysis3", reason="analysis3-specific security policy"
)


def test_installed_security_versions():
    versions, errors = check_installed()
    assert not errors, f"{versions}\n" + "\n".join(errors)


def handshake(client_context, server_context):
    """Complete an in-memory TLS handshake, or propagate the verification error."""
    client_in, client_out, server_in, server_out = (ssl.MemoryBIO() for _ in range(4))
    client = client_context.wrap_bio(client_in, client_out, server_hostname="localhost")
    server = server_context.wrap_bio(server_in, server_out, server_side=True)
    done = [False, False]
    for _ in range(20):
        for index, peer, output, incoming in (
            (0, client, client_out, server_in), (1, server, server_out, client_in)
        ):
            if not done[index]:
                try:
                    peer.do_handshake()
                    done[index] = True
                except ssl.SSLWantReadError:
                    pass
            if output.pending:
                incoming.write(output.read())
        if all(done):
            return
    pytest.fail("TLS handshake did not complete")


def contexts(tmp_path, scalar):
    # cryptography is already part of analysis3. No new test dependency.
    from cryptography import x509
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.x509.oid import ExtendedKeyUsageOID, NameOID

    root_key = ec.generate_private_key(ec.SECP384R1())
    intermediate_key = (ec.generate_private_key(ec.SECP384R1()) if scalar is None
                        else ec.derive_private_key(scalar, ec.SECP384R1()))
    leaf_key = ec.generate_private_key(ec.SECP384R1())

    def name(cn):
        return x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, cn)])

    def certificate(subject, issuer, key, signing_key, ca):
        now = datetime.now(timezone.utc)
        builder = (x509.CertificateBuilder().subject_name(subject).issuer_name(issuer)
                   .public_key(key.public_key()).serial_number(x509.random_serial_number())
                   .not_valid_before(now - timedelta(minutes=5)).not_valid_after(now + timedelta(days=1))
                   .add_extension(x509.BasicConstraints(ca=ca, path_length=None), critical=True)
                   .add_extension(x509.SubjectKeyIdentifier.from_public_key(key.public_key()), critical=False)
                   .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(signing_key.public_key()), critical=False)
                   .add_extension(x509.KeyUsage(digital_signature=True, content_commitment=False,
                                               key_encipherment=False, data_encipherment=False,
                                               key_agreement=False, key_cert_sign=ca, crl_sign=ca,
                                               encipher_only=False, decipher_only=False), critical=True))
        if not ca:
            builder = (builder.add_extension(x509.SubjectAlternativeName([x509.DNSName("localhost")]), critical=False)
                       .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.SERVER_AUTH]), critical=False))
        return builder.sign(signing_key, hashes.SHA384()).public_bytes(serialization.Encoding.PEM)

    root_name, intermediate_name = name("Local test root"), name("Local test intermediate")
    root = certificate(root_name, root_name, root_key, root_key, True)
    intermediate = certificate(intermediate_name, root_name, intermediate_key, root_key, True)
    leaf = certificate(name("localhost"), intermediate_name, leaf_key, intermediate_key, False)
    chain_path, key_path = tmp_path / "chain.pem", tmp_path / "key.pem"
    chain_path.write_bytes(leaf + intermediate)
    key_path.write_bytes(leaf_key.private_bytes(serialization.Encoding.PEM,
                                              serialization.PrivateFormat.PKCS8,
                                              serialization.NoEncryption()))
    key_path.chmod(0o600)
    client_context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    client_context.load_verify_locations(cadata=root.decode("ascii"))
    server_context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    server_context.load_cert_chain(chain_path, key_path)
    return client_context, server_context


def test_uncompromised_key_control(tmp_path):
    handshake(*contexts(tmp_path, None))


# All eight public weak-key values identified by the upstream incident. A fresh
# local issuer demonstrates that rejection matches the public key, not the issuer
# name or a specific certificate fingerprint (including cross-signed variants).
@pytest.mark.parametrize("scalar", [4, 56, 66, 115, 155, 156, 230, 237])
def test_compromised_intermediate_keys_rejected(tmp_path, scalar):
    client_context, server_context = contexts(tmp_path, scalar)
    with pytest.raises(ssl.SSLCertVerificationError) as exc:
        handshake(client_context, server_context)
    assert exc.value.verify_code == 28  # X509_V_ERR_CERT_REJECTED, as in CPython's test
