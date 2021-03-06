#include "gpu_automata_cuda.cuh"


// TODO Experiment with this function
#if 1
// 2D-GAME OF LIFE:
__device__ bool update_fun(bool *neighbors)
{
    int count = 0;
    for (int i= 9; i < 18; i++)
    {
        if (i != 13)
        {
            count += neighbors[i] ? 1 : 0;
        }
    }
    if (neighbors[13])
        return count == 2 || count == 3;
    else
        return count == 3;
}

#else
__device__ bool update_fun(bool *neighbors)
{
    int count = 0;
    for (int i = 0; i < 27; i++)
    {
        count += neighbors[i] ? 1 : 0;
    }
    return count > 3 && count < 9;

}

#endif

__device__ int get_index(int x, int y, int z, int xdim, int ydim, int zdim)
{
    return (x * ydim * zdim) + (y * zdim) + z;
}

// Put the values of the neighbors of the given position into the given array
// It is the responsibility of the caller to set initial values of the neighbors,
// which is relevant for the edge cases which are missing some neighbors.
// Each neighbor has a specific location in the neighbors array (see the
// "n_idx = get_index(...)" line), in case some update functions want to abandon
// symmetry
__device__ void get_neighbors(bool *neighbors, int idx, int xdim, int ydim, int zdim, bool *field)
{
    int x = idx / (ydim * zdim);
    int y = (idx % (ydim * zdim)) / zdim;
    int z = (idx % (ydim * zdim)) % zdim;

    int i_start = x == 0 ? 0 : -1;
    int j_start = y == 0 ? 0 : -1;
    int k_start = z == 0 ? 0 : -1;
    int i_end = x == xdim - 1 ? 0 : 1;
    int j_end = y == ydim - 1 ? 0 : 1;
    int k_end = z == zdim - 1 ? 0 : 1;

    for (int i = i_start; i <= i_end; i++)
    {
        for (int j = j_start; j <= j_end; j++)
        {
            for (int k = k_start; k <= k_end; k++)
            {
                if (i == 0 && y == 0 && k == 0)
                    continue;
                // Find the index within the neighbors array 
                int n_idx = get_index(i + 1, j + 1, k + 1, 3, 3, 3);
                neighbors[n_idx] = field[get_index(x + i, y + j, z + k, xdim, ydim, zdim)];
            }
        }
    }
}


__global__  void cuda_init_field_kernel(float *rands, bool *field, int length)
{
    // TODO Have more interesting field initialization
    int thread_idx = blockIdx.x * blockDim.x + threadIdx.x;
    for (int i = thread_idx; i < length; i += gridDim.x * blockDim.x)
    {
        field[i] = rands[i] < 0.1 ? true : false;
    }
}

__global__ void cuda_automaton_step_kernel(bool *old_field, bool *new_field,
        int xdim, int ydim, int zdim)
{
    // I'm not using shared memory for two reasons here: First is that it
    // starts overflowing at the uninterestingly low seeming size of 36x36x36,
    // and the first couple pages of google say nothing about what overflowing
    // shared mem does, so I don't want to do it in case it produces garbage
    // data.
    // The other reason (which should perhaps just be counted as part of the
    // first reason), is that the 36x36x36 bound comes from assuming that each
    // block can freely use all the shared memory of it's SMP, which will be
    // false so the shared mem would overflow even earlier.
    int thread_idx = blockIdx.x * blockDim.x + threadIdx.x;
    for (int i = thread_idx; i < xdim * ydim * zdim; i += gridDim.x * blockDim.x)
    {
        bool neighbors[27] = {};
        get_neighbors(neighbors, i, xdim, ydim, zdim, old_field);
        new_field[i] = update_fun(neighbors);
    }
}


void cuda_call_init_field_kernel(const unsigned int blocks,
        const unsigned int threadsPerBlock, float *rands,
        bool *field, int length)
{
    cuda_init_field_kernel<<<blocks, threadsPerBlock>>>(rands, field, length);
}

void cuda_call_automaton_step_kernel(const unsigned int blocks,
        const unsigned int threadsPerBlock,
        bool *old_field, bool *new_field, int xdim, int ydim, int zdim)
{
    cuda_automaton_step_kernel<<<blocks, threadsPerBlock>>>
        (old_field, new_field, xdim, ydim, zdim);
}
