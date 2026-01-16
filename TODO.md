 - [] A function/method/ctor etc doesn't just throw exceptions that
 thrown directly in the body of the function. Exceptions can also originate
 from any method/function/ctor that they call. 
 The questions is how far down the all tree we go as we could be making
 calls to hundreds of functions.  So I'm thinking going down the entire
 call tree is impractical. What may be practical is just going one
 level down - i.e. look at the source of each function that is directly called.
 When doing this would look at the comment for any 'throws' statements as it
 may document exeptions it throws as a result of calling child methods.
 By looking at the comments with a fully documented code base then we eventually
 we build a complete picture of what each method throws without having to
 go down the entire call tree - the comments essentially bubble the information
 up to us.