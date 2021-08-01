
using DrWatson
@quickactivate "Probabilistic medical segmentation"


SegmentationDisplayStr = """
Main module controlling displaying segmentations image and data

Description of nthe file structure
ModernGlUtil.jl 
    - copied utility functions from ModernGl.jl  
    - depends on external : ModernGL and  GLFW
PreperWindowHelpers.jl 
    - futher abstractions used in PreperWindow
    - depends on ModernGlUtil.jl 
shadersAndVerticies.jl 
    -store constant values of shader code and constant needed to render shapes
    -depends on external: ModernGL, GeometryTypes, GLFW
    -needs to be invoked only after initializeWindow() is invoked from PreperWindowHelpers module - becouse GLFW context mus be ready
PrepareWindow.jl 
    - collects functions and data and creates configured window with shapes needed to display textures and configures listening to mouse and keybourd inputs
    - depends on internal:ModernGlUtil,PreperWindowHelpers,shadersAndVerticies,OpenGLDisplayUtils
    - depends on external:ModernGL, GeometryTypes, GLFW
TextureManag.jl 
    - as image + masks are connacted by shaders into single texture this module  by controlling textures controlls image display
    - depends on external: ModernGL
    - depends on internal :OpenGLDisplayUtils
ReactToScroll.jl
    - functions needed to react to scrolling
    - depends on external: Rocket, GLFW
    - depends on internal : ForDisplayStructs.jl
ReactOnMouseClickAndDrag.jl   
    - functions needed to enable mouse interactions 
    - internal depentdencies: ForDisplayStructs, TextureManag,OpenGLDisplayUtils
    -external dependencies: Rocket, GLFW
ReactingToInput.jl - using Rocket.jl (reactivate functional programming ) enables reacting to user input
    - depends on external: Rocket, GLFW
    - depends on internal : ReactToScroll.jl, ForDisplayStructs.jl 
OpenGLDisplayUtils.jl - some utility functions used in diffrent parts of program
    - depends on external :GLFW, ModernGL 
"""
# @doc SegmentationDisplayStr
module SegmentationDisplay

using DrWatson
@quickactivate "Probabilistic medical segmentation"
export coordinateDisplay
export passDataForScrolling

using ModernGL, GLFW, Main.PrepareWindow, Main.TextureManag,Main.OpenGLDisplayUtils, Main.ForDisplayStructs,Main.Uniforms
using Main.ReactingToInput, Rocket, Setfield

#holds actor that is main structure that process inputs from GLFW and reacts to it
mainActor = sync(ActorWithOpenGlObjects())
#collecting all subsciptions  to be able to clean all later
subscriptions = []


coordinateDisplayStr = """
coordinating displaying - sets needed constants that are storeds in  forDisplayConstants; and configures interactions from GLFW events
listOfTextSpecs - holds required data needed to initialize textures
keeps also references to needed uniforms etc.
windowWidth::Int,windowHeight::Int - GLFW window dimensions
"""
@doc coordinateDisplayStr
function coordinateDisplay(listOfTextSpecs::Vector{Main.ForDisplayStructs.TextureSpec}
                        ,imageTextureWidth::Int
                        ,imageTextureHeight::Int
                        ,windowWidth::Int=Int32(800)
                        ,windowHeight::Int=Int32(800) )
 #creating window and event listening loop
    window,vertex_shader,fragment_shader ,shader_program,stopListening,vbo,ebo = Main.PrepareWindow.displayAll(windowWidth,windowHeight)

    #as we already has shader program ready we can  now initialize uniforms 
    masksTuplList, mainImageUnifs = createStructsDict(shader_program)
    # than we set those uniforms, open gl types and using data from arguments  to fill texture specifications
    listOfTextSpecsMapped= assignUniformsAndTypesToMasks(masksTuplList,listOfTextSpecs, mainImageUnifs ) |> 
    (specs)-> map((spec)-> setproperties(spec, (widthh= imageTextureWidth, heightt= imageTextureHeight )) 
                                            ,specs)

    #initializing object that holds data reqired for interacting with opengl 
    forDispObj =  forDisplayObjects(
        initializeTextures(shader_program, listOfTextSpecsMapped)
            ,window
            ,vertex_shader
            ,fragment_shader
            ,shader_program
            ,stopListening,
            Threads.Atomic{Bool}(0)
            ,vbo[]
            ,ebo[]
            ,imageTextureWidth
            ,imageTextureHeight
            ,windowWidth
            ,windowHeight
            ,0 # number of slices will be set when data for scrolling will come
            ,mainImageUnifs
    )

    #in order to clean up all resources while closing
    GLFW.SetWindowCloseCallback(window, (_) -> cleanUp())

    #wrapping the Open Gl and GLFW objects into an observable and passing it to the actor
    forDisplayConstantObesrvable = of(forDispObj)
    subscribe!(forDisplayConstantObesrvable, mainActor) # configuring
    registerInteractions()#passing needed subscriptions from GLFW

end #coordinateDisplay


passDataForScrollingStr =    """
is used to pass into the actor data that will be used for scrolling
onScrollData - list of tuples where first is the name of the texture that we provided and second is associated data (3 dimensional array of appropriate type)
"""
@doc passDataForScrollingStr
function passDataForScrolling(onScrollData::Vector{Tuple{String, Array{T, 3} where T}})
    #as we get data to scroll through we need to save the data about number of slices - important to controll scrolling
    mainActor.actor.mainForDisplayObjects.listOfTextSpecifications
    #wrapping the data into an observable and passing it to the actor
    forScrollData = of(onScrollData)
    subscribe!(forScrollData, mainActor) 
end


updateSingleImagesDisplayedStr =    """
enables updating just a single slice that is displayed - do not change what will happen after scrolling
one need to pass data to actor in 
listOfDataAndImageNames - vector of tuples whee first entry in tuple is name of texture given in the setup and second is 2 dimensional aray of appropriate type with image data
sliceNumber - the number to which we set slice in order to later start scrolling the scroll data from this point
"""
@doc updateSingleImagesDisplayedStr
function updateSingleImagesDisplayed( listOfDataAndImageNames::Vector{Tuple{String, Array{T, 2} where T}}, sliceNumber::Int64=1)
    forDispData = of((listOfDataAndImageNames,sliceNumber))
    subscribe!(forDispData, mainActor) 

end #updateSingleImagesDisplayed



registerInteractionsStr =    """
is using the actor that is instantiated in this module and connects it to GLFW context
by invoking appropriate registering functions and passing to it to the main Actor controlling input
"""
@doc registerInteractionsStr
function registerInteractions()
    subscriptionsInner = subscribeGLFWtoActor(mainActor)
    for el in subscriptionsInner
        push!(subscriptions,el)
    end #for


end

cleanUpStr =    """
In order to properly close displayer we need to :
 remove buffers that wer use 
 remove shaders 
 remove all textures
 unsubscibe all of the subscriptions to the mainActor
 finalize main actor and reinstantiate it
 close GLFW window
"""
@doc cleanUpStr
function cleanUp()
    GLFW.DestroyWindow(obj.window)

    glClearColor(0.0, 0.0, 0.1 , 1.0) # for a good begining
    #first we unsubscribe and give couple seconds for processes to stop
    for sub in subscriptions
        unsubscribe!(sub)
    end # for
    sleep(5)
    obj = mainActor.actor.mainForDisplayObjects
    #deleting textures
    glDeleteTextures(length(obj.listOfTextSpecifications), map(text->text.ID,obj.listOfTextSpecifications));
    #destroying buffers
    glDeleteBuffers(2,[obj.vbo,obj.ebo])
    #detaching shaders
    glDeleteShader(obj.fragment_shader);
    glDeleteShader(obj.vertex_shader);
    #destroying program
    glDeleteProgram(obj.shader_program)
    #finalizing and recreating main actor
end #cleanUp    


#pboId, DATA_SIZE = preparePixelBuffer(Int16,widthh,heightt,0)

# ##################
#clear color buffer
# glClearColor(0.0, 0.0, 0.1 , 1.0)
# #true labels
# glActiveTexture(GL_TEXTURE0 + 1); # active proper texture unit before binding
# glUniform1i(glGetUniformLocation(shader_program, "msk0"), 1);# we first look for uniform sampler in shader - here 
# trueLabels= createTexture(1,exampleLabels[210,:,:],widthh,heightt,GL_R8UI,GL_UNSIGNED_BYTE)#binding texture and populating with data
# #main image
# glActiveTexture(GL_TEXTURE0); # active proper texture unit before binding
# glUniform1i(glGetUniformLocation(shader_program, "Texture0"), 0);# we first look for uniform sampler in shader - here 
# mainTexture= createTexture(0,exampleDat[210,:,:],widthh,heightt,GL_R16I,GL_SHORT)#binding texture and populating with data
# #render
# basicRender()



############clean up

#remember to unsubscribe; remove textures; clear buffers and close window



end #SegmentationDisplay