#!/usr/bin/env python3
# Aligned 5-row block-letter banner (monospace-safe). Original glyphs.
import sys
F = {
'D':["████ ","█   █","█   █","█   █","████ "],
'Y':["█   █"," █ █ ","  █  ","  █  ","  █  "],
'N':["█   █","██  █","█ █ █","█  ██","█   █"],
'P':["████ ","█   █","████ ","█    ","█    "],
'R':["████ ","█   █","████ ","█  █ ","█   █"],
'O':[" ███ ","█   █","█   █","█   █"," ███ "],
'V':["█   █","█   █","█   █"," █ █ ","  █  "],
' ':["  ","  ","  ","  ","  "],
}
def banner(word):
    rows=["" for _ in range(5)]
    for ch in word.upper():
        g=F.get(ch, F[' '])
        for i in range(5):
            rows[i]+=g[i]+" "
    return "\n".join(rows)
if __name__=="__main__":
    print(banner(sys.argv[1] if len(sys.argv)>1 else "AGENTPROVIDER"))
