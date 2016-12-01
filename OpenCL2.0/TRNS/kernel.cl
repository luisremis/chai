/*
 * Copyright (c) 2016 University of Cordoba and University of Illinois
 * All rights reserved.
 *
 * Developed by:    IMPACT Research Group
 *                  University of Cordoba and University of Illinois
 *                  http://impact.crhc.illinois.edu/
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * with the Software without restriction, including without limitation the 
 * rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
 * sell copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 *      > Redistributions of source code must retain the above copyright notice,
 *        this list of conditions and the following disclaimers.
 *      > Redistributions in binary form must reproduce the above copyright
 *        notice, this list of conditions and the following disclaimers in the
 *        documentation and/or other materials provided with the distribution.
 *      > Neither the names of IMPACT Research Group, University of Cordoba, 
 *        University of Illinois nor the names of its contributors may be used 
 *        to endorse or promote products derived from this Software without 
 *        specific prior written permission.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 * CONTRIBUTORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS WITH
 * THE SOFTWARE.
 *
 */

#define _OPENCL_COMPILER_

#pragma OPENCL EXTENSION cl_khr_fp64 : enable
#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable
#pragma OPENCL EXTENSION cl_khr_global_int32_extended_atomics : enable

#include "support/common.h"

// GPU kernel ------------------------------------------------------------------------------------------
__kernel void PTTWAC_soa_asta(__global T *input, int A, int B, int b,
#ifdef OCL_2_0
    __global atomic_int *ptr_finished,
#else
    __global int *ptr_finished,
#endif
#ifdef OCL_2_0
    __global atomic_int *ptr_head,
#else
    __global int *ptr_head,
#endif
    __local int *done, __local int *gid_) {
    const int tid = get_local_id(0);
    int       m   = A * B - 1;

    if(tid == 0) // Dynamic fetch
#ifdef OCL_2_0
        gid_[0] = atomic_fetch_add(&ptr_head[0], 1);
#else
        gid_[0]         = atom_add(&ptr_head[0], 1);
#endif
    barrier(CLK_LOCAL_MEM_FENCE);

    while(gid_[0] < m) {
        int next_in_cycle = (gid_[0] * A) - m * (gid_[0] / B);
        if(next_in_cycle == gid_[0]) {
            if(tid == 0) // Dynamic fetch
#ifdef OCL_2_0
                gid_[0] = atomic_fetch_add(&ptr_head[0], 1);
#else
                gid_[0] = atom_add(&ptr_head[0], 1);
#endif
            barrier(CLK_LOCAL_MEM_FENCE);
            continue;
        }
        T   data1, data2, data3, data4;
        int i = tid;
        if(i < b)
            data1 = input[gid_[0] * b + i];
        i += get_local_size(0);
        if(i < b)
            data2 = input[gid_[0] * b + i];
        i += get_local_size(0);
        if(i < b)
            data3 = input[gid_[0] * b + i];
        i += get_local_size(0);
        if(i < b)
            data4 = input[gid_[0] * b + i];

        if(tid == 0) {
//make sure the read is not cached
#ifdef OCL_2_0
            done[0] = atomic_load(&ptr_finished[gid_[0]]);
#else
            done[0]     = atom_add(&ptr_finished[gid_[0]], 0);
#endif
        }
        barrier(CLK_LOCAL_MEM_FENCE);

        for(; done[0] == 0; next_in_cycle = (next_in_cycle * A) - m * (next_in_cycle / B)) {
            T backup1, backup2, backup3, backup4;
            i = tid;
            if(i < b)
                backup1 = input[next_in_cycle * b + i];
            i += get_local_size(0);
            if(i < b)
                backup2 = input[next_in_cycle * b + i];
            i += get_local_size(0);
            if(i < b)
                backup3 = input[next_in_cycle * b + i];
            i += get_local_size(0);
            if(i < b)
                backup4 = input[next_in_cycle * b + i];

            if(tid == 0) {
#ifdef OCL_2_0
                done[0] = atomic_exchange(&ptr_finished[next_in_cycle], (int)1);
#else
                done[0] = atomic_xchg(&ptr_finished[next_in_cycle], (int)1);
#endif
            }
            barrier(CLK_LOCAL_MEM_FENCE);

            if(!done[0]) {
                i = tid;
                if(i < b)
                    input[next_in_cycle * b + i] = data1;
                i += get_local_size(0);
                if(i < b)
                    input[next_in_cycle * b + i] = data2;
                i += get_local_size(0);
                if(i < b)
                    input[next_in_cycle * b + i] = data3;
                i += get_local_size(0);
                if(i < b)
                    input[next_in_cycle * b + i] = data4;
            }
            i = tid;
            if(i < b)
                data1 = backup1;
            i += get_local_size(0);
            if(i < b)
                data2 = backup2;
            i += get_local_size(0);
            if(i < b)
                data3 = backup3;
            i += get_local_size(0);
            if(i < b)
                data4 = backup4;
        }

        if(tid == 0) // Dynamic fetch
#ifdef OCL_2_0
            gid_[0] = atomic_fetch_add(&ptr_head[0], 1);
#else
            gid_[0]     = atom_add(&ptr_head[0], 1);
#endif
        barrier(CLK_LOCAL_MEM_FENCE);
    }
}
