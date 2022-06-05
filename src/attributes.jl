# mid-level API

"""
    HDF5.Attribute

A HDF5 attribute: this is a piece of metadata attached to an HDF5 `Group` or
`Dataset`. It acts like a `Dataset`, in that it has a defined datatype and
dataspace, and can `read` and `write` data to it.

See also
- [`open_attribute`](@ref)
- [`create_attribute`](@ref)
- [`read_attribute`](@ref)
- [`write_attribute`](@ref)
- [`delete_attribute`](@ref)
"""
mutable struct Attribute
    id::API.hid_t
    file::File

    function Attribute(id, file)
        dset = new(id, file)
        finalizer(close, dset)
        dset
    end
end
Base.cconvert(::Type{API.hid_t}, attr::Attribute) = attr
Base.unsafe_convert(::Type{API.hid_t}, attr::Attribute) = attr.id
function Base.close(obj::Attribute)
    if obj.id != -1
        if obj.file.id != -1 && isvalid(obj)
            API.h5a_close(obj)
        end
        obj.id = -1
    end
    nothing
end
name(attr::Attribute) = API.h5a_get_name(attr)


datatype(dset::Attribute) = Datatype(API.h5a_get_type(checkvalid(dset)), file(dset))
dataspace(attr::Attribute) = Dataspace(API.h5a_get_space(checkvalid(attr)))

function Base.write(obj::Attribute, x)
    dtype = datatype(x)
    try
        write_attribute(obj, dtype, x)
    finally
        close(dtype)
    end
end

"""
    read_attribute(parent::Union{File,Group,Dataset,Datatype}, name::AbstractString)

Read the value of the named attribute on the parent object.

# Example
```julia-repl
julia> HDF5.read_attribute(g, "time")
2.45
```
"""
function read_attribute(parent::Union{File,Group,Dataset,Datatype}, name::AbstractString)
    obj = open_attribute(parent, name)
    try
        return read(obj)
    finally
        close(obj)
    end
end
read_attribute(attr::Attribute, memtype::Datatype, buf) = API.h5a_read(attr, memtype, buf)

"""
    open_attribute(parent::Union{File,Group,Dataset,Datatype}, name::AbstractString)

Open the [`Attribute`](@ref) named `name` on the object `parent`.
"""
open_attribute(parent::Union{File,Object}, name::AbstractString, aapl::AttributeAccessProperties=AttributeAccessProperties()) =
    Attribute(API.h5a_open(checkvalid(parent), name, aapl), file(parent))

"""
    create_attribute(parent::Union{File,Object}, name::AbstractString, dtype::Datatype, space::Dataspace)
    create_attribute(parent::Union{File,Object}, name::AbstractString, data)

Create a new [`Attribute`](@ref) object named `name` on the object `parent`,
either by specifying the `Datatype` and `Dataspace` of the attribute, or by
providing the data. Note that no data will be written: use
[`write_attribute`](@ref) to write the data.
"""
function create_attribute(parent::Union{File,Object}, name::AbstractString, data; pv...)
    dtype = datatype(data)
    dspace = dataspace(data)
    obj = try
        create_attribute(parent, name, dtype, dspace; pv...)
    finally
        close(dspace)
    end
    return obj, dtype
end
function create_attribute(parent::Union{File,Object}, name::AbstractString, dtype::Datatype, dspace::Dataspace)
    attrid = API.h5a_create(checkvalid(parent), name, dtype, dspace, _attr_properties(name), API.H5P_DEFAULT)
    return Attribute(attrid, file(parent))
end

# generic method
write_attribute(attr::Attribute, memtype::Datatype, x) = API.h5a_write(attr, memtype, x)
# specific methods
function write_attribute(attr::Attribute, memtype::Datatype, str::AbstractString)
    strbuf = Base.cconvert(Cstring, str)
    GC.@preserve strbuf begin
        buf = Base.unsafe_convert(Ptr{UInt8}, strbuf)
        write_attribute(attr, memtype, buf)
    end
end
function write_attribute(attr::Attribute, memtype::Datatype, x::T) where {T<:Union{ScalarType,Complex{<:ScalarType}}}
    tmp = Ref{T}(x)
    write_attribute(attr, memtype, tmp)
end
function write_attribute(attr::Attribute, memtype::Datatype, strs::Array{<:AbstractString})
    p = Ref{Cstring}(strs)
    write_attribute(attr, memtype, p)
end
write_attribute(attr::Attribute, memtype::Datatype, ::EmptyArray) = nothing

"""
    write_attribute(parent::Union{File,Object}, name::AbstractString, data)

Write `data` as an [`Attribute`](@ref) named `name` on the object `parent`.
"""
function write_attribute(parent::Union{File,Object}, name::AbstractString, data; pv...)
    attr, dtype = create_attribute(parent, name, data; pv...)
    try
        write_attribute(attr, dtype, data)
    catch exc
        delete_attribute(parent, name)
        rethrow(exc)
    finally
        close(attr)
        close(dtype)
    end
    nothing
end

"""
    rename_attribute(parent::Union{File,Object}, oldname::AbstractString, newname::AbstractString)

Rename the [`Attribute`](@ref) of the object `parent` named `oldname` to `newname`.
"""
rename_attribute(parent::Union{File,Object}, oldname::AbstractString, newname::AbstractString) =
    API.h5a_rename(checkvalid(parent), oldname, newname)

"""
    delete_attribute(parent::Union{File,Object}, name::AbstractString)

Delete the [`Attribute`](@ref) named `name` on the object `parent`.
"""
delete_attribute(parent::Union{File,Object}, path::AbstractString) = API.h5a_delete(checkvalid(parent), path)


"""
    h5writeattr(filename, name::AbstractString, data::Dict)

Write `data` as attributes to the object at `name` in the HDF5 file `filename`.
"""
function h5writeattr(filename, name::AbstractString, data::Dict)
    file = h5open(filename, "r+")
    try
        obj = file[name]
        merge!(attrs(obj), data)
        close(obj)
    finally
        close(file)
    end
end

"""
    h5readattr(filename, name::AbstractString, data::Dict)

Read the attributes of the object at `name` in the HDF5 file `filename`, returning a `Dict`.
"""
function h5readattr(filename, name::AbstractString)
    local dat
    file = h5open(filename,"r")
    try
        obj = file[name]
        dat = Dict(attrs(obj))
        close(obj)
    finally
        close(file)
    end
    dat
end


struct AttributeDict <: AbstractDict{String,Any}
    parent::Object
end

"""
    attrs(object::Union{File,Group,Dataset,Datatype})

The attributes dictionary of `object`. Returns an `AttributeDict`, a `Dict`-like
object for accessing the attributes of `object`.

```julia
attrs(object)["name"] = value  # create/overwrite an attribute
attr = attrs(object)["name"]   # read an attribute
delete!(attrs(object), "name") # delete an attribute
keys(attrs(object))            # list the attribute names
```
"""
function attrs(parent::Object)
    return AttributeDict(parent)
end
attrs(file::File) = attrs(open_group(file, "."))

Base.haskey(attrdict::AttributeDict, path::AbstractString) = API.h5a_exists(checkvalid(attrdict.parent), path)
Base.length(attrdict::AttributeDict) = Int(object_info(attrdict.parent).num_attrs)

function Base.getindex(x::AttributeDict, name::AbstractString)
    haskey(x, name) || throw(KeyError(name))
    read_attribute(x.parent, name)
end
function Base.get(x::AttributeDict, name::AbstractString, default)
    haskey(x, name) || return default
    read_attribute(x.parent, name)
end
function Base.setindex!(attrdict::AttributeDict, val, name::AbstractString)
    if haskey(attrdict, name)
        # in case of an error, we write first to a temporary, then rename
        _name = tempname()
        try
            write_attribute(attrdict.parent, _name, val)
            delete_attribute(attrdict.parent, name)
            rename_attribute(attrdict.parent, _name, name)
        finally
            haskey(attrdict, _name) && delete_attribute(attrdict.parent, _name)
        end
    else
        write_attribute(attrdict.parent, name, val)
    end
end
Base.delete!(attrdict::AttributeDict, path::AbstractString) = delete_attribute(attrdict.parent, path)

function Base.keys(attrdict::AttributeDict)
    # faster than iteratively calling h5a_get_name_by_idx
    checkvalid(attrdict.parent)
    keyvec = sizehint!(String[], length(attrdict))
    API.h5a_iterate(attrdict.parent, IDX_TYPE[], ORDER[]) do _, attr_name, _
        push!(keyvec, unsafe_string(attr_name))
        return false
    end
    return keyvec
end

function Base.iterate(attrdict::AttributeDict)
    # constuct key vector, then iterate
    # faster than calling h5a_open_by_idx
    iterate(attrdict, (keys(attrdict), 1))
end
function Base.iterate(attrdict::AttributeDict, (keyvec, n))
    iter = iterate(keyvec, n)
    if isnothing(iter)
        return iter
    end
    key, nn = iter
    return (key => attrdict[key]), (keyvec, nn)
end

# deprecated, but retain definition as type is used in show.jl
struct Attributes
    parent::Union{File,Object}
end