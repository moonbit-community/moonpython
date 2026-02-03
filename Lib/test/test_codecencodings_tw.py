#
# test_codecencodings_tw.py
#   Codec encoding tests for ROC encodings.
#

import sys
import unittest

if sys.implementation.name == "moonpython":
    raise unittest.SkipTest("moonpython: codec registry/error handlers not implemented")

from test import multibytecodec_support

class Test_Big5(multibytecodec_support.TestBase, unittest.TestCase):
    encoding = 'big5'
    tstring = multibytecodec_support.load_teststring('big5')
    codectests = (
        # invalid bytes
        (b"abc\x80\x80\xc1\xc4", "strict",  None),
        (b"abc\xc8", "strict",  None),
        (b"abc\x80\x80\xc1\xc4", "replace", "abc\ufffd\ufffd\u8b10"),
        (b"abc\x80\x80\xc1\xc4\xc8", "replace", "abc\ufffd\ufffd\u8b10\ufffd"),
        (b"abc\x80\x80\xc1\xc4", "ignore",  "abc\u8b10"),
    )

if __name__ == "__main__":
    unittest.main()
