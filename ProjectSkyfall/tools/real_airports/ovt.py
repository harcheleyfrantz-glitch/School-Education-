import requests, re, io, os, json, time, sys
import pyarrow.parquet as pq
BASE = "https://overturemaps-us-west-2.s3.amazonaws.com/"
REL = "release/2026-10-21.0/"
S = requests.Session()

def list_keys(prefix):
    keys = []; tok = None
    while True:
        url = BASE + "?list-type=2&prefix=" + prefix + ("&continuation-token=" + requests.utils.quote(tok, safe="") if tok else "")
        t = S.get(url, timeout=60).text
        for k, sz in zip(re.findall(r"<Key>([^<]+)</Key>", t), re.findall(r"<Size>([^<]+)</Size>", t)):
            if k.endswith(".parquet"):
                keys.append((k, int(sz)))
        m = re.search(r"<NextContinuationToken>([^<]+)</NextContinuationToken>", t)
        if not m:
            break
        tok = m.group(1)
    return keys

class RangeFile(io.RawIOBase):
    BLK = 1 << 20
    def __init__(self, key, size):
        self.url = BASE + key; self.size = size; self.pos = 0; self.cache = {}; self.nreq = 0; self.nbytes = 0
    def readable(self): return True
    def seekable(self): return True
    def tell(self): return self.pos
    def seek(self, off, whence=0):
        if whence == 0: self.pos = off
        elif whence == 1: self.pos += off
        else: self.pos = self.size + off
        return self.pos
    def _fetch(self, a, b):
        for attempt in range(5):
            try:
                r = S.get(self.url, headers={"Range": "bytes=%d-%d" % (a, b - 1)}, timeout=120)
                if r.status_code in (200, 206):
                    self.nreq += 1; self.nbytes += len(r.content)
                    return r.content
            except Exception as e:
                pass
            time.sleep(1 + attempt * 2)
        raise IOError("fetch failed " + self.url)
    def read(self, n=-1):
        if n is None or n < 0: n = self.size - self.pos
        n = min(n, self.size - self.pos)
        if n <= 0: return b""
        a = self.pos; b = a + n
        out = bytearray()
        # big reads go straight through
        if n > 4 * self.BLK:
            out = self._fetch(a, b)
        else:
            b0 = a // self.BLK; b1 = (b - 1) // self.BLK
            for bi in range(b0, b1 + 1):
                if bi not in self.cache:
                    s0 = bi * self.BLK; s1 = min(self.size, s0 + self.BLK)
                    self.cache[bi] = self._fetch(s0, s1)
                blk = self.cache[bi]
                lo = max(a, bi * self.BLK) - bi * self.BLK
                hi = min(b, (bi + 1) * self.BLK) - bi * self.BLK
                out += blk[lo:hi]
        self.pos = b
        return bytes(out)
    def readinto(self, buf):
        d = self.read(len(buf)); buf[:len(d)] = d; return len(d)

def rg_bboxes(pf):
    md = pf.metadata
    names = [md.schema.column(i).path for i in range(md.num_columns)]
    idx = {n: i for i, n in enumerate(names)}
    out = []
    for r in range(md.num_row_groups):
        rg = md.row_group(r)
        def st(n):
            s = rg.column(idx[n]).statistics
            return s
        try:
            out.append((st("bbox.xmin").min, st("bbox.ymin").min, st("bbox.xmax").max, st("bbox.ymax").max, rg.num_rows))
        except Exception:
            out.append(None)
    return out

if __name__ == "__main__":
    t0 = time.time()
    keys = list_keys(REL + "theme=base/type=infrastructure/")
    print(len(keys), "infra files", sum(s for _, s in keys) / 1e9, "GB", time.time() - t0)
    k, sz = keys[0]
    f = RangeFile(k, sz)
    pf = pq.ParquetFile(f)
    print(pf.metadata.num_row_groups, "row groups", f.nreq, "req", f.nbytes, "bytes", time.time() - t0)
    print(pf.schema_arrow)
    print(rg_bboxes(pf)[:3])
