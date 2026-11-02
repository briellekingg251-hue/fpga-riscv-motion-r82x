// O2 shared helper functions (include inside a module body).
// Priority selection is done by arithmetic lowest-set-bit isolation
// (v & -v) plus OR-tree encoding. PDS (ADS 2022.2) lowers for-loop and
// if/else priority encoders into parallel muxes and then mis-optimizes
// comparisons of their output, which its built-in check rejects.
function automatic [7:0] oh_lo8(input [7:0] v);   // one-hot of the lowest set bit
    oh_lo8 = v & (~v + 8'd1);
endfunction
function automatic [7:0] rev8(input [7:0] v);
    rev8 = {v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]};
endfunction
function automatic [2:0] enc8(input [7:0] oh);    // one-hot -> index
    enc8 = {oh[4] | oh[5] | oh[6] | oh[7], oh[2] | oh[3] | oh[6] | oh[7], oh[1] | oh[3] | oh[5] | oh[7]};
endfunction
function automatic [7:0] oh_hi8(input [7:0] v);   // one-hot of the highest set bit
    oh_hi8 = rev8(oh_lo8(rev8(v)));
endfunction
function automatic [2:0] pe_lo8(input [7:0] v); pe_lo8 = enc8(oh_lo8(v)); endfunction
function automatic [2:0] pe_hi8(input [7:0] v); pe_hi8 = enc8(oh_hi8(v)); endfunction
function automatic [3:0] popc8(input [7:0] v);
    popc8 = {3'b0, v[0]} + {3'b0, v[1]} + {3'b0, v[2]} + {3'b0, v[3]} +
            {3'b0, v[4]} + {3'b0, v[5]} + {3'b0, v[6]} + {3'b0, v[7]};
endfunction
