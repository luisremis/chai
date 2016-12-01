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

#pragma OPENCL EXTENSION cl_khr_global_int32_base_atomics : enable
#pragma OPENCL EXTENSION cl_khr_global_int32_extended_atomics : enable

#include "support/common.h"

// OpenCL kernel ------------------------------------------------------------------------------------------
__kernel void TaskQueue_gpu(__global task_t *ptr_queues, __global atomic_int *ptr_num_task_in_queue,
    __global atomic_int *ptr_num_written_tasks, __global atomic_int *ptr_num_consumed_tasks, __global int *ptr_data,
    int gpuQueueSize, int iterations, __local task_t *t, __local int *last_queue) {

    const int tid       = get_local_id(0);
    int       tile_size = get_local_size(0);

    while(true) {
        // Fetch task
        if(tid == 0) {
            int  idx_queue = *last_queue;
            int  j, jj;
            bool not_done = true;

            do {
                if(atomic_load(ptr_num_consumed_tasks + idx_queue) == atomic_load(ptr_num_written_tasks + idx_queue)) {
                    idx_queue = (idx_queue + 1) % NUM_TASK_QUEUES;
                } else {
                    if(atomic_load(ptr_num_task_in_queue + idx_queue) > 0) {
                        j = atomic_fetch_sub(ptr_num_task_in_queue + idx_queue, 1) - 1;
                        if(j >= 0) {
                            t->id    = (ptr_queues + idx_queue * gpuQueueSize + j)->id;
                            t->op    = (ptr_queues + idx_queue * gpuQueueSize + j)->op;
                            jj       = atomic_fetch_add(ptr_num_consumed_tasks + idx_queue, 1) + 1;
                            not_done = false;
                            if(jj == atomic_load(ptr_num_written_tasks + idx_queue)) {
                                idx_queue = (idx_queue + 1) % NUM_TASK_QUEUES;
                            }
                            *last_queue = idx_queue;
                        } else {
                            idx_queue = (idx_queue + 1) % NUM_TASK_QUEUES;
                        }
                    } else {
                        idx_queue = (idx_queue + 1) % NUM_TASK_QUEUES;
                    }
                }
            } while(not_done);
        }
        barrier(CLK_LOCAL_MEM_FENCE); // It can be removed if work-group = wavefront

        // Compute task
        if(t->op == SIGNAL_STOP_KERNEL) {
            break;
        } else {
            if(t->op == SIGNAL_WORK_KERNEL) {
                for(int i = 0; i < iterations; i++) {
                    ptr_data[t->id * tile_size + tid] += tile_size;
                }

                ptr_data[t->id * tile_size + tid] += t->id;
            }
            if(t->op == SIGNAL_NOTWORK_KERNEL) {
                for(int i = 0; i < 1; i++) {
                    ptr_data[t->id * tile_size + tid] += tile_size;
                }

                ptr_data[t->id * tile_size + tid] += t->id;
            }
        }
    }
}
